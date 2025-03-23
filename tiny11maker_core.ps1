# Core functionality for Tiny11 image creation
function Invoke-Tiny11Maker {
    param (
        [string]$DriveLetter,
        [string]$ScratchDisk,
        [scriptblock]$WriteLog
    )

    # Create log directory in the script's location
    $logDir = Join-Path $PSScriptRoot "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $logFile = Join-Path $logDir "tiny11_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    # Start the transcript with error handling
    try {
        Start-Transcript -Path $logFile -ErrorAction Stop
        & $WriteLog "Log file created at: $logFile"
    } catch {
        & $WriteLog "Warning: Could not create log file: $_"
        & $WriteLog "Continuing without logging..."
    }

    $hostArchitecture = $Env:PROCESSOR_ARCHITECTURE
    
    # Clean up any existing files from previous runs
    & $WriteLog "Cleaning up any existing files from previous runs..."
    
    # Check for and cleanup any mounted images
    & $WriteLog "Checking for mounted images..."
    $mountedImages = Get-WindowsImage -Mounted
    foreach ($mountedImage in $mountedImages) {
        if ($mountedImage.Path -eq "$ScratchDisk\scratchdir") {
            & $WriteLog "Found previously mounted image at $($mountedImage.Path), attempting to dismount..."
            try {
                Dismount-WindowsImage -Path $mountedImage.Path -Discard -ErrorAction Stop
                & $WriteLog "Successfully dismounted previous image."
            } catch {
                & $WriteLog "Warning: Could not dismount previous image: $_"
                & $WriteLog "Please restart your computer and try again."
                return
            }
        }
    }
    
    Remove-Item -Path "$ScratchDisk\tiny11" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$ScratchDisk\scratchdir" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2  # Give Windows time to release file handles

    # Create fresh directories
    New-Item -ItemType Directory -Force -Path "$ScratchDisk\tiny11\sources" | Out-Null
    New-Item -ItemType Directory -Force -Path "$ScratchDisk\scratchdir" | Out-Null

    if ((Test-Path "$DriveLetter\sources\boot.wim") -eq $false -or (Test-Path "$DriveLetter\sources\install.wim") -eq $false) {
        if ((Test-Path "$DriveLetter\sources\install.esd") -eq $true) {
            & $WriteLog "Found install.esd, converting to install.wim..."
            
            # Get and display image information
            $imageInfo = Get-WindowsImage -ImagePath "$DriveLetter\sources\install.esd"
            & $WriteLog "Found $(($imageInfo | Measure-Object).Count) images in the ESD file"
            
            $index = Show-ImageInfoDialog -ImageInfo $imageInfo
            & $WriteLog "Selected index: $index"
            
            if (-not $index) {
                & $WriteLog "No image index selected. Exiting..."
                return
            }
            
            # Convert index to UInt32
            try {
                Write-Host "Debug: Attempting to convert index: $index"
                $indexNumber = [System.Convert]::ToUInt32($index)
                & $WriteLog "Converted index to number: $indexNumber"
            } catch {
                & $WriteLog "Error: Invalid image index selected. Exiting..."
                return
            }
            
            # Take ownership and set permissions on the destination path
            & $WriteLog "Setting up permissions..."
            $destinationWim = "$ScratchDisk\tiny11\sources\install.wim"
            
            # Create an empty file to set permissions
            New-Item -ItemType File -Force -Path $destinationWim | Out-Null
            
            # Take ownership and grant full permissions
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            & takeown /F $destinationWim /A
            & icacls $destinationWim /grant "${currentUser}:(F)"
            
            # Remove the empty file before conversion
            Remove-Item -Path $destinationWim -Force
            
            & $WriteLog "Converting install.esd to install.wim. This may take a while..."
            try {
                $sourcePath = "$DriveLetter\sources\install.esd"
                
                # Verify source file is accessible
                if (-not (Test-Path $sourcePath)) {
                    throw "Source ESD file not found or not accessible"
                }
                
                # Try the conversion
                Export-WindowsImage -SourceImagePath $sourcePath -SourceIndex $indexNumber -DestinationImagePath $destinationWim -Compressiontype Maximum -CheckIntegrity
                & $WriteLog "ESD to WIM conversion completed successfully."
            } catch {
                & $WriteLog "Error converting ESD to WIM: $_"
                & $WriteLog "Please make sure no other process is accessing the files and try again."
                return
            }
        } else {
            & $WriteLog "Can't find Windows OS Installation files in the specified Drive Letter.."
            & $WriteLog "Please enter the correct DVD Drive Letter.."
            return
        }
    }

    & $WriteLog "Copying Windows image..."
    Copy-Item -Path "$DriveLetter\*" -Destination "$ScratchDisk\tiny11" -Recurse -Force | Out-Null
    Set-ItemProperty -Path "$ScratchDisk\tiny11\sources\install.esd" -Name IsReadOnly -Value $false > $null 2>&1
    Remove-Item "$ScratchDisk\tiny11\sources\install.esd" > $null 2>&1
    & $WriteLog "Copy complete!"

    & $WriteLog "Getting image information:"
    $imageInfo = Get-WindowsImage -ImagePath "$ScratchDisk\tiny11\sources\install.wim"
    & $WriteLog "Found $(($imageInfo | Measure-Object).Count) images in the WIM file"
    
    $index = Show-ImageInfoDialog -ImageInfo $imageInfo
    & $WriteLog "Selected index: $index"
    
    if (-not $index) {
        & $WriteLog "No image index selected. Exiting..."
        return
    }
    
    # Convert index to UInt32
    try {
        Write-Host "Debug: Attempting to convert index: $index"
        $indexNumber = [System.Convert]::ToUInt32($index)
        & $WriteLog "Converted index to number: $indexNumber"
    } catch {
        & $WriteLog "Error: Invalid image index selected. Exiting..."
        return
    }
    
    & $WriteLog "Mounting Windows image. This may take a while."
    
    $wimFilePath = "$ScratchDisk\tiny11\sources\install.wim"
    & takeown "/F" $wimFilePath 
    & icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
    try {
        Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop
    } catch {
        # This block will catch the error and suppress it.
    }
    
    New-Item -ItemType Directory -Force -Path "$ScratchDisk\scratchdir" > $null
    
    # Try mounting with retries
    $maxRetries = 3
    $retryCount = 0
    $mounted = $false
    
    while (-not $mounted -and $retryCount -lt $maxRetries) {
        try {
            Mount-WindowsImage -ImagePath $ScratchDisk\tiny11\sources\install.wim -Index $indexNumber -Path $ScratchDisk\scratchdir -ErrorAction Stop
            $mounted = $true
            & $WriteLog "Successfully mounted Windows image."
        } catch {
            $retryCount++
            & $WriteLog "Attempt $retryCount of $maxRetries to mount image failed: $_"
            if ($retryCount -lt $maxRetries) {
                & $WriteLog "Waiting 5 seconds before retrying..."
                Start-Sleep -Seconds 5
            } else {
                & $WriteLog "Failed to mount image after $maxRetries attempts. Please restart your computer and try again."
                return
            }
        }
    }

    # Customize the Windows image
    & $WriteLog "Customizing Windows image..."
    
    # Remove unwanted features and packages
    & $WriteLog "Removing unwanted features and packages..."
    $removeFeatures = @(
        "Printing-PrintToPDFServices-Features",
        "Printing-XPSServices-Features",
        "WorkFolders-Client"
    )
    foreach ($feature in $removeFeatures) {
        Disable-WindowsOptionalFeature -Path "$ScratchDisk\scratchdir" -FeatureName $feature -Remove -NoRestart | Out-Null
    }

    # Remove unwanted provisioned packages
    & $WriteLog "Removing unwanted provisioned packages..."
    $packages = Get-AppxProvisionedPackage -Path "$ScratchDisk\scratchdir"
    $keepPackages = @(
        "Microsoft.WindowsCalculator",
        "Microsoft.WindowsStore",
        "Microsoft.WindowsNotepad",
        "Microsoft.WindowsTerminal",
        "Microsoft.DesktopAppInstaller",
        "Microsoft.SecHealthUI"
    )
    foreach ($package in $packages) {
        if ($keepPackages -notcontains $package.DisplayName) {
            Remove-AppxProvisionedPackage -Path "$ScratchDisk\scratchdir" -PackageName $package.PackageName | Out-Null
        }
    }

    # Unmount and save changes
    & $WriteLog "Unmounting Windows image and saving changes..."
    Dismount-WindowsImage -Path "$ScratchDisk\scratchdir" -Save

    # Create ISO file
    & $WriteLog "Creating ISO file..."
    $isoPath = Join-Path $PSScriptRoot "tiny11.iso"
    $oscdimgPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    
    if (Test-Path $oscdimgPath) {
        & $WriteLog "Creating ISO using oscdimg..."
        & $oscdimgPath -m -o -u2 -udfver102 -bootdata:2#p0,e,b"$ScratchDisk\tiny11\boot\etfsboot.com"#pEF,e,b"$ScratchDisk\tiny11\efi\microsoft\boot\efisys.bin" "$ScratchDisk\tiny11" "$isoPath"
        & $WriteLog "ISO file created at: $isoPath"
    } else {
        & $WriteLog "Error: oscdimg.exe not found. Please install Windows ADK."
        & $WriteLog "You can find the modified Windows files at: $ScratchDisk\tiny11"
        return
    }

    # Cleanup
    & $WriteLog "Cleaning up temporary files..."
    Remove-Item -Path "$ScratchDisk\scratchdir" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$ScratchDisk\tiny11" -Recurse -Force -ErrorAction SilentlyContinue

    & $WriteLog "Process completed successfully!"
    & $WriteLog "Your tiny11 ISO has been created at: $isoPath"

    # Stop the transcript if it was started
    try {
        Stop-Transcript
    } catch {
        # Ignore errors when stopping the transcript
    }
}

# Function to show image information and index selection dialog
function Show-ImageInfoDialog {
    param (
        [array]$ImageInfo
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Select Windows Image"
    $form.Size = New-Object System.Drawing.Size(600,400)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    # Create Panel for radio buttons (to enable scrolling if needed)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(10,10)
    $panel.Size = New-Object System.Drawing.Size(560,250)
    $panel.AutoScroll = $true

    # Variable to store selected index
    $script:selectedImageIndex = $null

    # Add radio buttons
    $buttonY = 10
    foreach ($image in $ImageInfo) {
        $radioButton = New-Object System.Windows.Forms.RadioButton
        $radioButton.Location = New-Object System.Drawing.Point(10,$buttonY)
        $radioButton.Size = New-Object System.Drawing.Size(540,20)
        $radioButton.Text = "Index $($image.ImageIndex) - $($image.ImageName) ($([math]::Round($image.ImageSize / 1GB, 2)) GB)"
        $radioButton.Tag = $image.ImageIndex
        $radioButton.Add_CheckedChanged({
            if ($this.Checked) {
                $script:selectedImageIndex = $this.Tag
            }
        })
        $panel.Controls.Add($radioButton)
        $buttonY += 25
    }

    $form.Controls.Add($panel)

    # Create OK button
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(250,320)
    $okButton.Size = New-Object System.Drawing.Size(75,23)
    $okButton.Text = "OK"
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($okButton)

    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $script:selectedImageIndex -ne $null) {
        Write-Host "Debug: Selected item index: $script:selectedImageIndex"
        return $script:selectedImageIndex.ToString()
    } else {
        return ""
    }
}