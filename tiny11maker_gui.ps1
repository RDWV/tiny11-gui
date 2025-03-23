# Enable debugging
#Set-PSDebug -Trace 1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Tiny11 Image Creator"
$form.Size = New-Object System.Drawing.Size(600,400)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

# Create a rich text box for logging
$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.Location = New-Object System.Drawing.Point(10,10)
$logBox.Size = New-Object System.Drawing.Size(560,300)
$logBox.ReadOnly = $true
$logBox.BackColor = [System.Drawing.Color]::Black
$logBox.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($logBox)

# Function to write to log
function Write-Log {
    param($Message)
    $logBox.AppendText("$Message`n")
    $logBox.ScrollToCaret()
}

# Create drive letter selection
$driveLabel = New-Object System.Windows.Forms.Label
$driveLabel.Location = New-Object System.Drawing.Point(10,320)
$driveLabel.Size = New-Object System.Drawing.Size(100,20)
$driveLabel.Text = "Drive Letter:"
$form.Controls.Add($driveLabel)

$driveComboBox = New-Object System.Windows.Forms.ComboBox
$driveComboBox.Location = New-Object System.Drawing.Point(120,320)
$driveComboBox.Size = New-Object System.Drawing.Size(50,20)
$driveComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
# Add drive letters C-Z
65..90 | ForEach-Object { $driveComboBox.Items.Add([char]$_) }
$driveComboBox.SelectedIndex = 0
$form.Controls.Add($driveComboBox)

# Create start button
$startButton = New-Object System.Windows.Forms.Button
$startButton.Location = New-Object System.Drawing.Point(480,320)
$startButton.Size = New-Object System.Drawing.Size(90,30)
$startButton.Text = "Start"
$startButton.Add_Click({
    $startButton.Enabled = $false
    $driveComboBox.Enabled = $false
    
    # Get selected values
    $DriveLetter = $driveComboBox.SelectedItem.ToString() + ":"
    $ScratchDisk = $PSScriptRoot -replace '[\\]+$', ''
    
    Write-Log "Starting Tiny11 image creation..."
    Write-Log "Drive Letter: $DriveLetter"
    Write-Log "Scratch Disk: $ScratchDisk"
    
    # Check if PowerShell execution is restricted
    if ((Get-ExecutionPolicy) -eq 'Restricted') {
        Write-Log "Your current PowerShell Execution Policy is set to Restricted."
        Write-Log "Please run PowerShell as Administrator and execute: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
        $startButton.Enabled = $true
        $driveComboBox.Enabled = $true
        return
    }
    
    # Check and run as admin if required
    $adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])
    $myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
    $myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
    $adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
    
    if (! $myWindowsPrincipal.IsInRole($adminRole)) {
        Write-Log "Restarting Tiny11 image creator as admin in a new window..."
        $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell"
        $newProcess.Arguments = $myInvocation.MyCommand.Definition
        $newProcess.Verb = "runas"
        [System.Diagnostics.Process]::Start($newProcess)
        $form.Close()
        return
    }
    
    # Start the main process
    try {
        # Import and run the core script
        . "$PSScriptRoot\tiny11maker_core.ps1"
        Invoke-Tiny11Maker -DriveLetter $DriveLetter -ScratchDisk $ScratchDisk -WriteLog ${function:Write-Log}
        Write-Log "Process completed successfully!"
    }
    catch {
        Write-Log "Error occurred: $_"
    }
    finally {
        $startButton.Enabled = $true
        $driveComboBox.Enabled = $true
    }
})
$form.Controls.Add($startButton)

# Show the form
$form.ShowDialog() 