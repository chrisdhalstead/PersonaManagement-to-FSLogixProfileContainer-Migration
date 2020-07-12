
#*************************************************************************************
#Set Variables
#$Tab = [char]9
$VbCrLf = “`r`n” 
$un = $env:USERNAME #Local Logged in User
$sComputer = $env:COMPUTERNAME #Local Computername
$sLogName = "PMtoFSL#$un.log" #Log File Name
$sLogPath = $PSScriptRoot #Current Directory
$sLogPath = $sLogPath + "\Logs"
#Create Log Directory if it doesn't exist
if (!(Test-Path $sLogPath)){New-Item -ItemType Directory -Path $sLogPath -Force}
$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName
$tempdir = $env:TEMP
Add-Content $sLogFile -Value $vbcrlf
$sLogTitle = "Starting Script as $un from $scomputer*************************************"
Add-Content $sLogFile -Value $sLogTitle

Function Write-Log {
    [CmdletBinding()]

    Param(
    
    [Parameter(Mandatory=$True)]
    [System.Object]
    $Message
  
    )
    $Stamp = (Get-Date).toString("MM/dd/yyyy HH:mm:ss")
    $Line = "$Stamp $Level $Message"
  
    $isWritten = $false
  
    do {
        try {
            Add-Content $sLogFile -Value $Line
            $isWritten = $true
            }
        catch {}
    } until ($isWritten)
       
    }

function ConvertFromPMtoFSL {

#Create empty array
$allprofiles =@()

#Loop through all v6 profiles on the Persona Management share
foreach ($v6profile in $v6profiles) 
        
    #Check for flag file to indicate it was already processed
    {if(test-path $v6profile\PM2FSLflag.txt)
        {continue}
            else
        {$allprofiles+=$v6profile}
        }

#Show form and allow user to choose which profiles to convert
#Save selcted profiles into a variable
$oldprofiles = $allprofiles | out-gridview -OutputMode Multiple -Title "Select users to migrate from Persona Management to FSLogix" 

#Process each selected profile
foreach ($old in $oldprofiles) {
    
    $usersam = Split-Path ($old -split ".V6")[0] -leaf
    $usersid = (New-Object System.Security.Principal.NTAccount($usersam)).translate([System.Security.Principal.SecurityIdentifier]).Value

    Write-Log -Message "Processing $usersam"

    #Create a new folder for the users FSLogix Profile Container    
    $newfolder = join-path $newprofilepath ($usersid+"_"+$usersam) 

    #if $nfolder doesn't exist - create it
    if (!(test-path $newfolder)) 
        {New-Item -Path $newfolder -ItemType directory | Out-Null
        write-log -Message "Folder $newfolder created"
        }
 
    else {write-log -Message "$newfolder already exists"}

    $aclpresult = & icacls $newfolder /grant $env:userdomain\$usersam`:`(OI`)`(CI`)F /T 
    Write-Log "Granting $sam control of the folder: $aclpresult"

    #Make the user owner of the folder
    $acloresult = & icacls $newfolder /setowner "$env:userdomain\$usersam" /T /C 
    Write-Log "Making $sam owner of the folder: $acloresult"

    # sets vhd to \\nfolderpath\profile_username.vhd
    $vhdpath = Join-Path $newfolder ("Profile_"+$usersam+"."+$script:diskformat)
    # diskpart commands

if (!(Test-Path $vhdpath))
{
    #Convert GB to MB
    $script:disksize = $script:disksize -as [int]
    $vhdsize = $script:disksize
    $vhdsize *= 1024
      
    #Get random available local drive letter for temporary use
    $dl = Get-ChildItem function:[d-z]: -n | Where-Object{ !(test-path $_) } | Get-Random
    $dl = $dl.trimend(":")

    #Create VHD/x with Diskpart      
    NEW-ITEM -Force -path $tempdir -name dp.txt -itemtype "file"
    ADD-CONTENT -Path $tempdir"\dp.txt" "create vdisk file=$vhdpath type=expandable maximum=$vhdsize"
    ADD-CONTENT -Path $tempdir"\dp.txt" "select vdisk file=$vhdpath"
    ADD-CONTENT -Path $tempdir"\dp.txt" "attach vdisk"
    ADD-CONTENT -Path $tempdir"\dp.txt" "create partition primary"
    ADD-CONTENT -Path $tempdir"\dp.txt" "format FS=NTFS QUICK LABEL=Profile-$usersam"
    ADD-CONTENT -Path $tempdir"\dp.txt" "assign letter=$dl"
    $dpresult = DISKPART /S $tempdir"\dp.txt"
    Remove-Item $tempdir"\dp.txt"

    write-log -message "Creating VHD/x: $dpresult"

    $fslprofiledir =  $dl+":\Profile"

    #Create Profile Directory on the Profile Container
    New-Item -Path $fslprofiledir -ItemType directory | Out-Null

    #sleep for 2 seconds
    Start-Sleep -s 2
 
    #Set Permissions on FSL Profile Container
    $admgp = "Domain Admins"
    & icacls $fslprofiledir /grant $admgp`:`(OI`)`(CI`)F
    & icacls $fslprofiledir /setowner SYSTEM
    & icacls $fslprofiledir /grant SYSTEM`:`(OI`)`(CI`)F
    & icacls $fslprofiledir /grant $env:userdomain\$usersam`:`(OI`)`(CI`)F
    & icacls $fslprofiledir /inheritance:r
} 

    # Create a Reg file for the FSLogix Profile Container at E:\Profile\AppData\local\FSLogix\ProfileData.reg
    $RegText = "Windows Registry Editor Version 5.00`r`n`r`n
    [HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$UserSID]`r`n
    `"ProfileImagePath`"=`"C:\\Users\\$UserSAM`"`r`n
    `"Flags`"=dword:00000000`r`n
    `"State`"=dword:00000000`r`n
    `"ProfileLoadTimeLow`"=dword:00000000`r`n
    `"ProfileLoadTimeHigh`"=dword:00000000`r`n
    `"RefCount`"=dword:00000000`r`n
    `"RunLogonScriptSync`"=dword:00000000`r`n"

    Write-Log -Message "Created Registry Key"
          
    #Copying $old to $vhd"
    try {& robocopy $old $fslprofiledir /E /Purge /r:0 /log+:$sLogPath"\robocopy_$usersam.log" | Out-Null}
        catch { $err= $_ }if (!$err){write-log -message "Copying $old to $vhdpath"}else{Write-Log -message "$ Failed to Copy $old to $vhdpath"}

    #Add Flad to Persona Directory    
    out-file $old"\PM2FSLflag.txt"

    #Create FSLogix Directory
    New-Item -Path $fslprofiledir"\AppData\Local\FSLogix" -ItemType Directory | Out-Null
    
    #Add Reg data to FSL Profile
    New-Item -Path $fslprofiledir"\AppData\Local\FSLogix\ProfileData.reg" -ItemType File | Out-Null
    $regtext | Out-File $fslprofiledir"\AppData\Local\FSLogix\ProfileData.reg" -Encoding ascii
        
    #Remove Drive Letter
    Get-Volume -Drive $dl | Get-Partition | Remove-PartitionAccessPath -accesspath "$dl`:\"

    #Detach VHD/x From Local Machine
    NEW-ITEM -Force -path $tempdir -name dp.txt -itemtype "file"
    ADD-CONTENT -Path $tempdir"\dp.txt" "select vdisk file=$vhdpath"
    ADD-CONTENT -Path $tempdir"\dp.txt" "detach vdisk"
    $dpresult = DISKPART /S $tempdir"\dp.txt"
    Remove-Item $tempdir"\dp.txt"
    write-log -Message $dpresult
 
}

}

#-----------------------------------------------------------[Script Execution]------------------------------------------------------------

#Requires -RunAsAdministrator
Write-Log -Message "Starting Execution of Script******************************************"

$script:newprofilepath = (Read-Host -Prompt "Provide FSLogix Profile Container UNC Path") #"\\controlcenter\fslogix" 
Write-Log -Message "FSLogix Profile Container UNC Path $script:newprofilepath"

$script:oldprofilepath = (Read-Host -Prompt "Provide Persona Management Profile Path") #"\\controlcenter\vdi_profiles"
Write-Log -Message "Persona Management Profile Path $script:oldprofilepath"

$script:disksize = (Read-Host -Prompt "Enter the size of the Profile Container to be created in GB") #"10"
Write-Log -Message "Size of Profile Container set to $script:oldprofilepath GB"

$script:diskformat = (Read-Host -Prompt "Enter the disk format VHD or VHDX") #"VHDX"
Write-Log -Message "Persona Management Profile Path $script:oldprofilepath"

#Look for .V6 profiles in the Persona Management Directory
$script:v6profiles = Get-ChildItem $script:oldprofilepath | Where-Object{$_.name -like "*.V6"}  | select-object -Expand fullname | sort-object

if (($script:v6profiles).count -eq 0)  

{

    Write-Log -Message "There are no v6 profiles at $script:oldprofilepath"
    write-Host  "There are no v6 profiles at $script:oldprofilepath"

}

else 

{
    
    ConvertFromPMtoFSL

}

write-log("Finishing Script***********************************************************")



