# ============================================================
# INSTALL PC - Executable unique
# Version alpha2 - CleBitlocker + CompteAdmin integres (PNL OU ordi), Balabolka portable,
#              log AppendAllText, compte capture AVANT install, raccourci sans parenthèse
# ============================================================

$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    if ($PSCommandPath) {
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    } else {
        $self = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        Start-Process $self -Verb RunAs
    }
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

# --- Anti-double-lancement ---
$mutex = New-Object System.Threading.Mutex($false, "Global\InstallPC_Mutex")
if (-not $mutex.WaitOne(0)) {
    [System.Windows.Forms.MessageBox]::Show("Une installation est deja en cours sur ce PC. Attends sa fin.", "Install_PC") | Out-Null
    exit
}

# --- Log ---
$Source = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
$LogFile = Join-Path $Source "install_log.txt"
function Log-File {
    param([string]$msg)
    try {
        $line = ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg)
        [System.IO.File]::AppendAllText($LogFile, $line + [Environment]::NewLine)
    } catch {}
}

# --- Capture du compte cible AVANT toute modification ---
$targetUser = $null
$active = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
if ($active) {
    $n = ($active -split '\\')[-1]
    if ($n -like "ordi*") { $targetUser = $n }
}
if (-not $targetUser) {
    $c = Get-ChildItem "C:\Users" -Directory -Filter "ordi*" -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($c) { $targetUser = $c.Name }
}

# --- URLs ---
$UrlPolices    = "https://github.com/user-attachments/files/35419368/Polices.zip"
$UrlBalabolka  = "https://www.cross-plus-a.com/balabolka_portable.zip"

$PublicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
$UserDesktop   = [Environment]::GetFolderPath("Desktop")
$Desktop = $PublicDesktop
$testFile = Join-Path $PublicDesktop (".write_test_" + (Get-Random))
try {
    "test" | Out-File $testFile -Force -ErrorAction Stop
    Remove-Item $testFile -Force -ErrorAction SilentlyContinue
} catch { $Desktop = $UserDesktop }

# --- Lecture config.json ---
$cfgPath = Join-Path $Source "config.json"
if (-not (Test-Path $cfgPath)) {
    $cfg = [PSCustomObject]@{
        bitlocker = $true; voix = $true; balabolka = $true; handy = $false
        extensions = $true; pdfx = $false; onenote = $false; polices = $false; bureautique = $false
    }
} else {
    try { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json }
    catch {
        $cfg = [PSCustomObject]@{
            bitlocker = $true; voix = $true; balabolka = $true; handy = $false
            extensions = $true; pdfx = $false; onenote = $false; polices = $false; bureautique = $false
        }
    }
}

function Test-Internet {
    try { $null = Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop; return $true } catch { return $false }
}

# ============================================================
# CLE BITLOCKER + COMPTE ADMIN (integree)
# ============================================================
function Invoke-CleBitlocker {
    # Autorisation : PC "PNL*" OU session "ordi*"
    if (($env:COMPUTERNAME -notlike "PNL*") -and ($env:USERNAME -notlike "ordi*")) {
        $null = [System.Windows.MessageBox]::Show(
            "Cet outil est reserve aux PC et comptes lycéens de la Region Normandie.`nSi tu es dans le bon cadre, rapproche-toi du mediateur numerique.",
            "Accès refusé", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    # Uniquement depuis le disque C
    $SelfPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ($SelfPath.Substring(0,1) -ne "C") {
        $null = [System.Windows.MessageBox]::Show(
            "Copie et lance cet outil depuis le disque C: de cet ordi.",
            "Information", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    try {
        $ComputerName = $env:COMPUTERNAME
        $UserName     = $env:USERNAME
        $Date         = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $FilePath = Join-Path $Desktop ("Clé-BitLocker_" + $ComputerName + "_" + $UserName + "_" + $Date + ".txt")

        $BLV = Get-BitLockerVolume -MountPoint "C:"
        $Recovery = ($BLV.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }).RecoveryPassword

        $OtherAccounts = Get-LocalUser | Where-Object { $_.Name -ne $UserName -and $_.Name -ne "Admin" } | Select-Object -ExpandProperty Name
        $AccountsText = $OtherAccounts -join ", "
        if (-not $AccountsText) { $AccountsText = "Aucun autre compte local" }

        $Text = @(
            "==== INFORMATIONS DE CET ORDINATEUR ===="
            "Nom du PC   : $ComputerName"
            "Utilisateur : $UserName"
            "Date        : $(Get-Date)"
            ""
            "==== CLE BITLOCKER DU DISQUE DUR (C:) ===="
            $Recovery
            ""
            "==== COMPTES DE CONNEXION ===="
            "Compte Region : $UserName@educ.normandie.fr (existe tant que tu es lycéen)"
            "Compte personnel : .\Admin"
            "Autres comptes locaux eventuels : $AccountsText"
        )
        $Text | Out-File -FilePath $FilePath -Encoding UTF8 -Force

        # Compte admin local
        $LocalUser = "Admin"
        $jour = (Get-Date).DayOfWeek
        $PlainPassword = switch ($jour) {
            "Monday"    { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("bGF2YW5kZQ==")) }
            "Tuesday"   { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("bWF1dmU=")) }
            "Wednesday" { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("bWVudGhl")) }
            "Thursday"  { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("amF1bmU=")) }
            "Friday"    { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("dmVydA==")) }
            "Saturday"  { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("c2FmcmFu")) }
            "Sunday"    { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("ZGVuaW0=")) }
        }
        $Password = ConvertTo-SecureString $PlainPassword -AsPlainText -Force
        if (-not (Get-LocalUser -Name $LocalUser -ErrorAction SilentlyContinue)) {
            New-LocalUser -Name $LocalUser -Password $Password | Out-Null
            net user $LocalUser /logonpasswordchg:yes | Out-Null
        }
        $AdminGroup = (Get-LocalGroup | Where-Object { $_.SID -eq "S-1-5-32-544" }).Name
        Add-LocalGroupMember -Group $AdminGroup -Member $LocalUser -ErrorAction SilentlyContinue | Out-Null

        $msg = @(
            "Clé BitLocker obtenue !"
            "La clé BitLocker de ce PC est :"
            "$Recovery"
            "Elle est enregistrée dans un fichier sur le bureau."
            "Il FAUT absolument en garder une copie ailleurs !"
            "Prends une photo de cet écran dès maintenant !"
            ""
            "Nouveau compte créé !"
            "Ton compte .\Admin a été créé."
            "Son mot de passe va t'être donné par le médiateur numérique."
            "Ce mot de passe DOIT être changé dès la première connexion."
            ""
            "À RETENIR :"
            "Ton compte personnel : .\Admin"
            "Compte Région : $UserName@educ.normandie.fr"
            "Tant que tu es lycéen, le compte Région peut être utilisé."
            "Lorsque tu ne seras plus lycéen, utilise ton compte personnel."
        ) -join [Environment]::NewLine
        $null = [System.Windows.MessageBox]::Show($msg, "Confirmation", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return $true
    } catch {
        $null = [System.Windows.MessageBox]::Show($_.Exception.Message, "Erreur", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return $false
    }
}

# ============================================================
# INTERFACE
# ============================================================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Installation des logiciels" Height="540" Width="520"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#FFFFFF" FontFamily="Segoe UI">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Border Grid.Row="0" Padding="24,18,24,18">
            <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                    <GradientStop Color="#003C7D" Offset="0"/>
                    <GradientStop Color="#0066B3" Offset="1"/>
                </LinearGradientBrush>
            </Border.Background>
            <StackPanel>
                <TextBlock Text="Installation des logiciels" FontSize="22" FontWeight="Bold" Foreground="White"/>
                <TextBlock Text="Tout se fait automatiquement. Connexion internet requise." FontSize="13" Foreground="#D6E4F0" Margin="0,4,0,0"/>
            </StackPanel>
        </Border>
        <Border x:Name="BannerWarn" Grid.Row="1" Background="#FFF3E0" Padding="16,12,16,12" Visibility="Collapsed">
            <TextBlock Text="Pas de connexion internet detectee. Certaines installations ne pourront pas se faire." FontSize="13" Foreground="#B26A00" TextWrapping="Wrap"/>
        </Border>
        <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" Padding="24,12,24,8">
            <StackPanel x:Name="PanelStatus"/>
        </ScrollViewer>
        <StackPanel Grid.Row="3" Margin="24,8,24,20">
            <ProgressBar x:Name="Progress" Height="10" Minimum="0" Maximum="100" Value="0" Foreground="#00A651" Background="#E6E6E6" BorderThickness="0"/>
            <TextBlock x:Name="StatusText" Text="Preparation..." FontSize="12" Foreground="#444444" Margin="0,8,0,0"/>
            <Button x:Name="BtnDone" Content="Terminer" Height="48" FontSize="16" FontWeight="Bold" Foreground="White" BorderThickness="0" Cursor="Hand" Margin="0,12,0,0" Visibility="Collapsed">
                <Button.Template>
                    <ControlTemplate TargetType="Button">
                        <Border Background="#003C7D" CornerRadius="10">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Button.Template>
            </Button>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)
$PanelStatus = $Window.FindName("PanelStatus")
$Progress    = $Window.FindName("Progress")
$StatusText  = $Window.FindName("StatusText")
$BtnDone     = $Window.FindName("BtnDone")
$BannerWarn  = $Window.FindName("BannerWarn")

function Add-Step {
    param([string]$text)
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = "  En cours : $text"
    $tb.FontSize = 13
    $tb.Margin = New-Object System.Windows.Thickness(0,3,0,3)
    $tb.Tag = $text
    $PanelStatus.Children.Add($tb) | Out-Null
    Log-File "DEBUT $text"
    $Window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
}
function Done-Step {
    param([string]$text)
    foreach ($c in $PanelStatus.Children) { if ($c.Tag -eq $text) { $c.Text = "  OK  $text"; $c.Foreground = [System.Windows.Media.Brushes]::Green } }
    Log-File "OK   $text"
    $Window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
}
function Fail-Step {
    param([string]$text)
    foreach ($c in $PanelStatus.Children) { if ($c.Tag -eq $text) { $c.Text = "  !!  $text"; $c.Foreground = [System.Windows.Media.Brushes]::Orange } }
    Log-File "ECHEC $text"
    $Window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
}
function Skip-Step {
    param([string]$text)
    foreach ($c in $PanelStatus.Children) { if ($c.Tag -eq $text) { $c.Text = "  --  $text"; $c.Foreground = [System.Windows.Media.Brushes]::Gray } }
    Log-File "SKIP $text"
}

# ============================================================
# EXECUTION
# ============================================================
$Window.Add_ContentRendered({
    $online = Test-Internet
    if (-not $online) { $BannerWarn.Visibility = "Visible" }
    Log-File "=== Debut. En ligne=$online. Compte cible=$targetUser. PC=$env:COMPUTERNAME. User=$env:USERNAME ==="

    $totalSteps = 3
    if ($cfg.bitlocker)   { $totalSteps++ }
    if ($cfg.voix)        { $totalSteps++ }
    if ($cfg.balabolka)   { $totalSteps++ }
    if ($cfg.handy)       { $totalSteps++ }
    if ($cfg.pdfx)        { $totalSteps++ }
    if ($cfg.onenote)     { $totalSteps++ }
    if ($cfg.polices)     { $totalSteps++ }
    if ($cfg.extensions)  { $totalSteps++ }
    if ($cfg.bureautique) { $totalSteps++ }
    $stepIndex = 0
    function Inc-Progress { $script:stepIndex++; $Progress.Value = [math]::Min(100, ($script:stepIndex / $totalSteps * 100)) }

    Add-Step "Desactivation SmartScreen"
    try {
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
        Set-ItemProperty -Path $regPath -Name "EnableSmartScreen" -Value 0 -Type DWord
        Done-Step "Desactivation SmartScreen"
    } catch { Fail-Step "Desactivation SmartScreen" }
    Inc-Progress

    # --- Cle BitLocker (integree, message photo conserve) ---
    if ($cfg.bitlocker) {
        Add-Step "Cle BitLocker + Compte Admin"
        try {
            $res = Invoke-CleBitlocker
            if ($res) { Done-Step "Cle BitLocker + Compte Admin" } else { Fail-Step "Cle BitLocker (refusee)" }
        } catch { Fail-Step "Cle BitLocker + Compte Admin" }
        Inc-Progress
    }

    # --- Voix NVSA (GitHub, francais silencieux) ---
    if ($cfg.voix) {
        Add-Step "Voix naturelles NVSA"
        if (-not $online) { Fail-Step "Voix NVSA (hors-ligne)" }
        else {
            try {
                $nvsaDst = "C:\Tools\NVSA"
                $api = "https://api.github.com/repos/gexgd0419/NaturalVoiceSAPIAdapter/releases/latest"
                $release = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "InstallPC" } -UseBasicParsing
                $asset = $release.assets | Where-Object { $_.name -like "*x86_x64.zip" } | Select-Object -First 1
                if (-not $asset) { throw "Asset x86_x64 introuvable" }
                $zipPath = Join-Path $env:TEMP $asset.name
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing -TimeoutSec 120
                Unblock-File $zipPath -ErrorAction SilentlyContinue
                if (Test-Path $nvsaDst) { Remove-Item $nvsaDst -Recurse -Force -ErrorAction SilentlyContinue }
                New-Item -ItemType Directory -Path $nvsaDst -Force | Out-Null
                Expand-Archive -Path $zipPath -DestinationPath $nvsaDst -Force
                $installer = Get-ChildItem -Path $nvsaDst -Filter "Installer.exe" -Recurse | Select-Object -First 1
                if ($installer) {
                    Unblock-File $installer.FullName -ErrorAction SilentlyContinue
                    Start-Process $installer.FullName -ArgumentList "/S" -WorkingDirectory $installer.DirectoryName -Wait
                    Done-Step "Voix naturelles NVSA"
                } else { Fail-Step "Voix naturelles NVSA" }
            } catch { Fail-Step "Voix naturelles NVSA" }
        }
        Inc-Progress
    }

    # --- Balabolka (portable, lien officiel) ---
    if ($cfg.balabolka) {
        Add-Step "Balabolka (portable)"
        if (-not $online) { Fail-Step "Balabolka (hors-ligne)" }
        else {
            try {
                $zipP = Join-Path $env:TEMP "balabolka.zip"
                $dst  = "C:\Tools\balabolka_portable"
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $UrlBalabolka -OutFile $zipP -UseBasicParsing -TimeoutSec 90
                Unblock-File $zipP -ErrorAction SilentlyContinue
                if (Test-Path $dst) { Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue }
                New-Item -ItemType Directory -Path $dst -Force | Out-Null
                Expand-Archive -Path $zipP -DestinationPath $dst -Force
                $exe = Get-ChildItem -Path $dst -Filter "balabolka.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($exe) {
                    Unblock-File $exe.FullName -ErrorAction SilentlyContinue
                    $WScript = New-Object -ComObject WScript.Shell
                    $lnk = $WScript.CreateShortcut((Join-Path $Desktop "Balabolka.lnk"))
                    $lnk.TargetPath = $exe.FullName
                    $lnk.WorkingDirectory = $exe.DirectoryName
                    $lnk.Description = "Balabolka - lecture a voix haute"
                    $lnk.Save()
                    Done-Step "Balabolka (portable)"
                } else { Fail-Step "Balabolka (exe introuvable)" }
                Remove-Item $zipP -Force -ErrorAction SilentlyContinue
            } catch { Fail-Step "Balabolka (portable)" }
        }
        Inc-Progress
    }

    # --- Handy (winget) ---
    if ($cfg.handy) {
        Add-Step "Handy (dictee vocale)"
        if (-not $online) { Fail-Step "Handy (hors-ligne)" }
        else {
            try {
                Start-Process "winget" -ArgumentList "install -e --id cjpais.Handy --accept-package-agreements --accept-source-agreements --silent" -Wait -NoNewWindow
                Done-Step "Handy (dictee vocale)"
            } catch { Fail-Step "Handy (dictee vocale)" }
        }
        Inc-Progress
    }

    # --- PDF-XChange (winget) ---
    if ($cfg.pdfx) {
        Add-Step "PDF-XChange Editor"
        if (-not $online) { Fail-Step "PDF-XChange (hors-ligne)" }
        else {
            try {
                Start-Process "winget" -ArgumentList "install -e --id TrackerSoftware.PDF-XChangeEditor --accept-package-agreements --accept-source-agreements --silent" -Wait -NoNewWindow
                Done-Step "PDF-XChange Editor"
            } catch { Fail-Step "PDF-XChange Editor" }
        }
        Inc-Progress
    }

    # --- OneNote (winget msstore) ---
    if ($cfg.onenote) {
        Add-Step "OneNote"
        if (-not $online) { Fail-Step "OneNote (hors-ligne)" }
        else {
            try {
                $already = Get-AppxPackage -Name "Microsoft.Office.OneNote" -ErrorAction SilentlyContinue
                if ($already) { Done-Step "OneNote" }
                else {
                    Start-Process "winget" -ArgumentList "install --id 9WZDNCRFJ3PZ --source msstore --accept-package-agreements --accept-source-agreements --silent --disable-interactivity" -Wait -NoNewWindow
                    $deadline = (Get-Date).AddMinutes(2); $installed = $false
                    while ((Get-Date) -lt $deadline -and -not $installed) {
                        Start-Sleep -Seconds 5
                        if (Get-AppxPackage -Name "Microsoft.Office.OneNote" -ErrorAction SilentlyContinue) { $installed = $true }
                    }
                    if ($installed) { Done-Step "OneNote" } else { Fail-Step "OneNote (non installe)" }
                }
            } catch { Fail-Step "OneNote" }
        }
        Inc-Progress
    }

    # --- Polices (zip, durci) ---
    if ($cfg.polices) {
        Add-Step "Polices dyslexie"
        if (-not $online) { Fail-Step "Polices (hors-ligne)" }
        else {
            try {
                $zipP = Join-Path $env:TEMP "polices.zip"
                $extP = Join-Path $env:TEMP "polices_ext"
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $UrlPolices -OutFile $zipP -UseBasicParsing -TimeoutSec 90
                Unblock-File $zipP -ErrorAction SilentlyContinue
                $bytes = [System.IO.File]::ReadAllBytes($zipP)
                if ($bytes.Length -lt 4 -or $bytes[0] -ne 0x50 -or $bytes[1] -ne 0x4B) { throw "Lien invalide (pas un zip)" }
                if (Test-Path $extP) { Remove-Item $extP -Recurse -Force -ErrorAction SilentlyContinue }
                New-Item -ItemType Directory -Path $extP -Force | Out-Null
                Expand-Archive -Path $zipP -DestinationPath $extP -Force
                $fontDir = [Environment]::GetFolderPath("Fonts")
                $fontFiles = Get-ChildItem -Path $extP -Recurse -File | Where-Object { $_.Extension -in ".ttf",".otf",".ttc" }
                foreach ($f in $fontFiles) {
                    Copy-Item $f.FullName -Destination $fontDir -Force
                    $regName = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
                    $value = $f.BaseName + " (TrueType)"
                    if ($f.Extension -eq ".otf") { $value = $f.BaseName + " (OpenType)" }
                    New-ItemProperty -Path $regName -Name $value -Value (Join-Path $fontDir $f.Name) -PropertyType String -Force | Out-Null
                }
                Remove-Item $zipP -Force -ErrorAction SilentlyContinue
                Remove-Item $extP -Recurse -Force -ErrorAction SilentlyContinue
                Done-Step "Polices dyslexie"
            } catch { Fail-Step "Polices dyslexie" }
        }
        Inc-Progress
    }

    # --- Extensions (desinstallables) ---
    if ($cfg.extensions) {
        Add-Step "Extensions navigateur"
        try {
            $extSettings = '{"ifjafammaookpiajfbedmacfldaiamgg":{"installation_mode":"normal_installed","update_url":"https://clients2.google.com/service/update2/crx"},"emgfmfgandmhbgleikkoaebngboghfpe":{"installation_mode":"normal_installed","update_url":"https://clients2.google.com/service/update2/crx"},"kohfgcgbkjodfcfkcackpagifgbcmimk":{"installation_mode":"normal_installed","update_url":"https://clients2.google.com/service/update2/crx"}}'
            $edgePol = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
            if (-not (Test-Path $edgePol)) { New-Item -Path $edgePol -Force | Out-Null }
            Set-ItemProperty -Path $edgePol -Name "ExtensionSettings" -Value $extSettings -Type String
            $chromePol = "HKLM:\SOFTWARE\Policies\Google\Chrome"
            if (-not (Test-Path $chromePol)) { New-Item -Path $chromePol -Force | Out-Null }
            Set-ItemProperty -Path $chromePol -Name "ExtensionSettings" -Value $extSettings -Type String
            Done-Step "Extensions navigateur"
        } catch { Fail-Step "Extensions navigateur" }
        Inc-Progress
    }

    # --- Bureautique (dormant) ---
    if ($cfg.bureautique) {
        Add-Step "Logiciels bureautique"
        if (-not $online) { Fail-Step "Bureautique (hors-ligne)" }
        else {
            try {
                $apps = @("TheDocumentFoundation.LibreOffice","Google.Chrome","languagetool.LanguageTool")
                foreach ($app in $apps) { Start-Process "winget" -ArgumentList "install -e --id $app --accept-package-agreements --accept-source-agreements --silent" -Wait -NoNewWindow }
                Done-Step "Logiciels bureautique"
            } catch { Fail-Step "Logiciels bureautique" }
        }
        Inc-Progress
    }

    # --- Raccourci CompteRegion (cible forcee, garde-fou Admin, sans parenthèse dans le nom) ---
   Add-Step "Raccourci CompteRegion"
    try {
        Get-ChildItem $Desktop -Filter "Mes fichiers*.lnk" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        if ($targetUser) {
            $userFolder = "C:\Users\$targetUser"
            if (-not (Test-Path $userFolder)) {
                $profiles = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" -ErrorAction SilentlyContinue
                foreach ($p in $profiles) {
                    $pp = (Get-ItemProperty -Path $p.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
                    if ($pp -and ($pp -imatch "\\$targetUser$")) { $userFolder = $pp; break }
                }
            }
            if ($userFolder -match "\\Admin$") { throw "cible admin refusee" }
            if (-not (Test-Path $userFolder)) { throw "dossier introuvable" }
            $lnkPath = Join-Path $Desktop ("Mes fichiers - $targetUser.lnk")
            $shell = New-Object -ComObject WScript.Shell
            $lnk = $shell.CreateShortcut($lnkPath)
            $lnk.TargetPath = $userFolder
            $lnk.Arguments = ""
            $lnk.WorkingDirectory = $userFolder
            $lnk.Description = "Dossier personnel $targetUser"
            $lnk.IconLocation = "shell32.dll,4"
            $lnk.Save()
            $lnk = $null
            [GC]::Collect()
            Log-File "Raccourci ecrit -> $userFolder"
            Done-Step "Raccourci CompteRegion ($targetUser)"
        } else { Skip-Step "Raccourci CompteRegion" }
    } catch { Fail-Step "Raccourci CompteRegion : $($_.Exception.Message)" }
    Inc-Progress

    Add-Step "Reactivation SmartScreen"
    try {
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        Set-ItemProperty -Path $regPath -Name "EnableSmartScreen" -Value 1 -Type DWord
        Done-Step "Reactivation SmartScreen"
    } catch { Fail-Step "Reactivation SmartScreen" }
    Inc-Progress

    $Progress.Value = 100
    if ($online) { $StatusText.Text = "Termine ! Tu peux fermer." }
    else { $StatusText.Text = "Termine (hors-ligne : certaines installations ont echoue)." }
    $StatusText.Foreground = [System.Windows.Media.Brushes]::Green
    $StatusText.FontWeight = [System.Windows.FontWeights]::Bold
    $BtnDone.Visibility = "Visible"
    Log-File "=== Fin ==="
})

$BtnDone.Add_Click({ $Window.Close() })
$null = $Window.ShowDialog()
