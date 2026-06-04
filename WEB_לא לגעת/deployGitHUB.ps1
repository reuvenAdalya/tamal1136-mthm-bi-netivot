# 1. טעינת רכיבים גרפיים
try { Add-Type -AssemblyName Microsoft.VisualBasic } catch {}

# --- פונקציית תעתיק חסינה ---
function Get-TransliteratedName {
    param([string]$InputString)
    $map = @{}
    $chars = @(
        @{c=0x05D0; v='a'}, @{c=0x05D1; v='b'}, @{c=0x05D2; v='g'}, @{c=0x05D3; v='d'},
        @{c=0x05D4; v='h'}, @{c=0x05D5; v='v'}, @{c=0x05D6; v='z'}, @{c=0x05D7; v='h'},
        @{c=0x05D8; v='t'}, @{c=0x05D9; v='i'}, @{c=0x05DA; v='k'}, @{c=0x05DB; v='k'},
        @{c=0x05DC; v='l'}, @{c=0x05DD; v='m'}, @{c=0x05DE; v='m'}, @{c=0x05DF; v='n'},
        @{c=0x05E0; v='n'}, @{c=0x05E1; v='s'}, @{c=0x05E2; v='a'}, @{c=0x05E3; v='p'},
        @{c=0x05E4; v='p'}, @{c=0x05E5; v='ts'}, @{c=0x05E6; v='ts'}, @{c=0x05E7; v='q'},
        @{c=0x05E8; v='r'}, @{c=0x05E9; v='sh'}, @{c=0x05EA; v='t'}
    )
    foreach ($item in $chars) {
        $charObj = [char]$item.c
        if (-not $map.ContainsKey($charObj)) { $map.Add($charObj, $item.v) }
    }
    $result = ""
    if ($InputString) {
        $InputString.ToLower().ToCharArray() | ForEach-Object {
            if ($map.ContainsKey($_)) { $result += $map[$_] }
            elseif ($_ -match '[a-z0-9]') { $result += $_ }
            elseif ($_ -eq ' ' -or $_ -eq '-' -or $_ -eq '_') { $result += '-' }
        }
    }
    return ($result -replace '-+', '-').Trim('-')
}

# --- 2. וידוא חיבור וזיהוי משתמש ---
$username = gh api user --jq .login 2>$null
if (!$username) { 
    Write-Host "ERROR: Please run 'gh auth login' first." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 
}

# --- 3. זיהוי נתיבים ושמות ---
$currentFolder = Get-Item $PSScriptRoot
$workTreeFolder = $currentFolder.Parent
$projectFolder = $workTreeFolder.Parent
$fullFolderName = $projectFolder.Name
$parts = $fullFolderName -split ' ', 2 
$projectPart = if ($parts.Count -gt 1) { $parts[1] } else { $fullFolderName }
$suggestedName = Get-TransliteratedName -InputString $projectPart

# --- 4. אישור פרטים (Repo + Topic) ---
$repoName = [Microsoft.VisualBasic.Interaction]::InputBox("Confirm Repo Name:", "GitHub Deploy", $suggestedName)
if (!$repoName) { exit }

$topicName = [Microsoft.VisualBasic.Interaction]::InputBox("Enter Project Topic:", "GitHub Topic", "havitot")
if (!$topicName) { $topicName = "havitot" }

# --- 5. עבודת Git + פתרון Box ---
$gitDir = Join-Path $currentFolder.FullName ".git"
$workTree = $workTreeFolder.FullName

# הגדרת משתני סביבה בנתיב יחסי כדי שגיט יעבוד עם עברית
$env:GIT_DIR = Join-Path $currentFolder.Name ".git"
$env:GIT_WORK_TREE = "."

Set-Location $workTree

# רישום התיקיות כבטוחות ל-Git (פתרון ל-Box)
git config --global --add safe.directory $workTree.Replace('\', '/')
git config --global --add safe.directory $currentFolder.FullName.Replace('\', '/')

if (!(Test-Path $gitDir)) {
    git init
    git checkout -b main 2>$null
}
git branch -M main

# יצירה ב-GitHub או חיבור לקיים
$remoteExists = git remote | Where-Object { $_ -eq "origin" }
if (!$remoteExists) {
    Write-Host "Setting up GitHub Repository..." -ForegroundColor Cyan
    # מנסה ליצור ריפו חדש
    gh repo create $repoName --public 2>$null
    
    # בודק אם ה-remote נוצר (אם הריפו כבר קיים בגיטהאב הפקודה הקודמת נכשלת)
    $remoteExists = git remote | Where-Object { $_ -eq "origin" }
    if (!$remoteExists) {
        Write-Host "Repository might already exist, adding remote manually..." -ForegroundColor Gray
        git remote add origin "https://github.com/$username/$repoName.git"
    }
}

# עדכון תגית
gh repo edit $repoName --add-topic $topicName

# העלאת קבצים
Write-Host "Pushing files to GitHub..." -ForegroundColor White
git add .
git commit -m "Automated update" 2>$null
git push -u origin main --force

# --- 6. הפעלת Pages (שימוש ב-API הישיר) ---
Write-Host "Enforcing GitHub Pages configuration..." -ForegroundColor Yellow
Start-Sleep -Seconds 5
$apiPath = "repos/$username/$repoName/pages"
gh api -X POST $apiPath -f "source[branch]=main" -f "source[path]=/" --silent 2>$null
gh repo edit $repoName --enable-pages --pages-branch main --pages-path / 2>$null

# --- 7. סיום, כתיבת קובץ ופתיחת דפדפן ---
$siteUrl = "https://$username.github.io/$repoName/"

# יצירת קובץ הטקסט בתיקייה המקומית
$urlFilePath = Join-Path $currentFolder.FullName "webURL.txt"
$siteUrl | Out-File -FilePath $urlFilePath -Encoding utf8
Write-Host "Created file: webURL.txt with the live link." -ForegroundColor Gray

Write-Host "  $siteUrl" -ForegroundColor White
Write-Host ("=" * 50) -ForegroundColor Green

# פתיחת האתר החי בדפדפן
Start-Process $siteUrl

Write-Host "`nPress any key to close..." -ForegroundColor Yellow
[void]($Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown"))