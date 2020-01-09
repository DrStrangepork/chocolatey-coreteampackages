﻿function Get-LocalizedWellKnownPrincipalName {
  param (
    [Parameter(Mandatory = $true)]
    [Security.Principal.WellKnownSidType] $WellKnownSidType
  )
  $sid = New-Object -TypeName 'System.Security.Principal.SecurityIdentifier' -ArgumentList @($WellKnownSidType, $null)
  $account = $sid.Translate([Security.Principal.NTAccount])

  return $account.Value
}

function Protect-InstallFolder {
  param(
    [string]$packageName,
    [string]$defaultInstallPath,
    [string]$folder
  )
  Write-Debug "Ensure-Permissions"

  if ($folder.ToLower() -ne $defaultInstallPath.ToLower()) {
    Write-Warning "Installation folder is not the default. Not changing permissions. Please ensure your installation is secure."
    return
  }

  # Everything from here on out applies to the default installation folder

  if (!(Test-ProcessAdminRights)) {
    throw "Installation of $packageName to default folder requires Administrative permissions. Please run from elevated prompt."
  }

  $currentEA = $ErrorActionPreference
  $ErrorActionPreference = 'Stop'
  try {
    # get current acl
    $acl = (Get-Item $folder).GetAccessControl('Access,Owner')

    Write-Debug "Removing existing permissions."
    $acl.Access | ForEach-Object { $acl.RemoveAccessRuleAll($_) }

    $inheritanceFlags = ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit)
    $propagationFlags = [Security.AccessControl.PropagationFlags]::None

    $rightsFullControl = [Security.AccessControl.FileSystemRights]::FullControl
    $rightsModify = [Security.AccessControl.FileSystemRights]::Modify
    $rightsReadExecute = [Security.AccessControl.FileSystemRights]::ReadAndExecute

    Write-Output "Restricting write permissions to Administrators"
    $builtinAdmins = Get-LocalizedWellKnownPrincipalName -WellKnownSidType ([Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid)
    $adminsAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($builtinAdmins, $rightsFullControl, $inheritanceFlags, $propagationFlags, "Allow")
    $acl.SetAccessRule($adminsAccessRule)
    $localSystem = Get-LocalizedWellKnownPrincipalName -WellKnownSidType ([Security.Principal.WellKnownSidType]::LocalSystemSid)
    $localSystemAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($localSystem, $rightsFullControl, $inheritanceFlags, $propagationFlags, "Allow")
    $acl.SetAccessRule($localSystemAccessRule)
    $builtinUsers = Get-LocalizedWellKnownPrincipalName -WellKnownSidType ([Security.Principal.WellKnownSidType]::BuiltinUsersSid)
    $usersAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($builtinUsers, $rightsReadExecute, $inheritanceFlags, $propagationFlags, "Allow")
    $acl.SetAccessRule($usersAccessRule)

    $allowCurrentUser = $env:ChocolateyInstallAllowCurrentUser -eq 'true'
    if ($allowCurrentUser) {
      # get current user
      $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()

      if ($currentUser.Name -ne $localSystem) {
        $userAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($currentUser.Name, $rightsModify, $inheritanceFlags, $propagationFlags, "Allow")
        Write-Warning 'Adding Modify permission for current user due to $env:ChocolateyInstallAllowCurrentUser. This could lead to escalation of privilege attacks. Consider not allowing this.'
        $acl.SetAccessRule($userAccessRule)
      }
    }
    else {
      Write-Debug 'Current user no longer set due to possible escalation of privileges - set $env:ChocolateyInstallAllowCurrentUser="true" if you require this.'
    }

    Write-Debug "Set Owner to Administrators"
    $builtinAdminsSid = New-Object System.Security.Principal.SecurityIdentifier([Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
    $acl.SetOwner($builtinAdminsSid)

    Write-Debug "Default Installation folder - removing inheritance with no copy"
    $acl.SetAccessRuleProtection($true, $false)

    # enact the changes against the actual
    (Get-Item $folder).SetAccessControl($acl)
  }
  catch {
    Write-Warning "Not able to set permissions for $folder."
    Write-Warning $_
  }
  $ErrorActionPreference = $currentEA
}