# Variables configured in form
$group = $form.gridGroups
$usersToAdd = $form.members.leftToRight
$usersToRemove = $form.members.rightToLeft

# Global variables
# $EntraIdOrganization = ""
# $EntraIdAppId = ""
# $EntraIdCertificateBase64String = ""
# $EntraIdCertificatePassword = ""

# Fixed values
# PowerShell commands to import
$commands = @(
    "Add-DistributionGroupMember"
    , "Remove-DistributionGroupMember"
)

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
function Get-MSEntraCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificateBase64String,
        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CertificatePassword
    )
    try {
        $rawCertificate = [system.convert]::FromBase64String($CertificateBase64String)
        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawCertificate, $CertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
        Write-Output $certificate
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion functions

try {
    # Import module
    $actionMessage = "importing module [ExchangeOnlineManagement]"
        
    $importModuleSplatParams = @{
        Name        = "ExchangeOnlineManagement"
        Cmdlet      = $commands
        Verbose     = $false
        ErrorAction = "Stop"
    }

    $null = Import-Module @importModuleSplatParams

    Write-Verbose "Imported module [ExchangeOnlineManagement]"

    # Convert base64 certificate string to certificate object
    $actionMessage = "converting base64 certificate string to certificate object"

    $certificate = Get-MSEntraCertificate -CertificateBase64String $EntraIdCertificateBase64String -CertificatePassword $EntraIdCertificatePassword

    Write-Verbose "Converted base64 certificate string to certificate object"

    # Connect to Microsoft Exchange Online
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/connect-exchangeonline?view=exchange-ps
    $actionMessage = "connecting to Microsoft Exchange Online"

    $createExchangeSessionSplatParams = @{
        Organization          = $EntraIdOrganization
        AppID                 = $EntraIdAppId
        Certificate           = $certificate
        CommandName           = $commands
        ShowBanner            = $false
        ShowProgress          = $false
        TrackPerformance      = $false
        SkipLoadingCmdletHelp = $true
        SkipLoadingFormatData = $true
        ErrorAction           = "Stop"
    }

    $null = Connect-ExchangeOnline @createExchangeSessionSplatParams

    # Add members
    $actionMessage = "adding users as member to group with displayName [$($group.displayName)] and id [$($group.id)]"
    foreach ($userToAdd in $usersToAdd) {
        try {
            # Add member to group
            # docs: https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/add-distributiongroupmember?view=exchange-ps
            $actionMessage = "adding user with displayName [$($userToAdd.displayName)] and id [$($userToAdd.id)] as member to group with displayName [$($group.displayName)] and id [$($group.id)]"
   
            $addGroupMemberSplatParams = @{
                Identity                        = $group.id
                Member                          = $userToAdd.id
                BypassSecurityGroupManagerCheck = $true
                Confirm                         = $false
                ErrorAction                     = "Stop"
                Verbose                         = $false
            }

            $addGroupMemberResponse = Add-DistributionGroupMember @addGroupMemberSplatParams

            # Send auditlog to HelloID   
            $Log = @{
                Action            = "GrantMembership" # optional. ENUM (undefined = default) 
                System            = "ExchangeOnline" # optional (free format text) 
                Message           = "Added user with displayName [$($userToAdd.displayName)] and id [$($userToAdd.id)] as member to group with displayName [$($group.displayName)] and id [$($group.id)]." # required (free format text) 
                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                TargetDisplayName = $group.displayName # optional (free format text)
                TargetIdentifier  = $group.id # optional (free format text)
            }
            Write-Information -Tags "Audit" -MessageData $log
        }
        catch {
            $ex = $PSItem
            if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {
                $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)"
                $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)"
            }
            else {
                $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
                $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            }

            if ($ex.CategoryInfo.Reason -eq 'MemberAlreadyExistsException') {
                # Send auditlog to HelloID    
                $Log = @{
                    Action            = "GrantMembership" # optional. ENUM (undefined = default) 
                    System            = "ExchangeOnline" # optional (free format text) 
                    Message           = "Skipped $($actionMessage). Reason: User is already a member." # required (free format text) 
                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                    TargetDisplayName = $group.displayName # optional (free format text)
                    TargetIdentifier  = $group.id # optional (free format text)
                }
                Write-Information -Tags "Audit" -MessageData $log
            }
            else {
                # Send auditlog to HelloID   
                $Log = @{
                    Action            = "GrantMembership" # optional. ENUM (undefined = default) 
                    System            = "ExchangeOnline" # optional (free format text) 
                    Message           = $auditMessage # required (free format text) 
                    IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                    TargetDisplayName = $group.displayName # optional (free format text)
                    TargetIdentifier  = $group.id # optional (free format text)
                }
                Write-Information -Tags "Audit" -MessageData $log
                Write-Warning $warningMessage
                Write-Error $auditMessage
            }
        }
    }

    # Remove members
    $actionMessage = "removing users as member from group with displayName [$($group.displayName)] and id [$($group.id)]"
    foreach ($userToRemove in $usersToRemove) {
        try {
            # Remove member from group
            # docs: https://learn.microsoft.com/en-us/powershell/module/exchange/remove-distributiongroupmember?view=exchange-ps
            $actionMessage = "removing user with displayName [$($userToRemove.displayName)] and id [$($userToRemove.id)] as member from group with displayName [$($group.displayName)] and id [$($group.id)]"
   
            $removeGroupMemberSplatParams = @{
                Identity                        = $group.id
                Member                          = $userToRemove.id
                BypassSecurityGroupManagerCheck = $true
                Confirm                         = $false
                ErrorAction                     = "Stop"
                Verbose                         = $false
            }

            $removeGroupMemberResponse = Remove-DistributionGroupMember @removeGroupMemberSplatParams

            # Send auditlog to HelloID   
            $Log = @{
                Action            = "RevokeMembership" # optional. ENUM (undefined = default) 
                System            = "ExchangeOnline" # optional (free format text) 
                Message           = "Removed user with displayName [$($userToRemove.displayName)] and id [$($userToRemove.id)] as member from group with displayName [$($group.displayName)] and id [$($group.id)]." # required (free format text) 
                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                TargetDisplayName = $group.displayName # optional (free format text)
                TargetIdentifier  = $group.id # optional (free format text)
            }
            Write-Information -Tags "Audit" -MessageData $log
        }
        catch {
            $ex = $PSItem
            if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {
                $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)"
                $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)"
            }
            else {
                $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
                $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            }

            if ($ex.CategoryInfo.Reason -eq 'MemberNotFoundException' -or $ex.CategoryInfo.Reason -eq 'ADTransientException') {
                # Send auditlog to HelloID   
                $Log = @{
                    Action            = "RevokeMembership" # optional. ENUM (undefined = default) 
                    System            = "ExchangeOnline" # optional (free format text) 
                    Message           = "Skipped $($actionMessage). Reason: User is already no longer a member." # required (free format text) 
                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                    TargetDisplayName = $group.displayName # optional (free format text)
                    TargetIdentifier  = $group.id # optional (free format text)
                }
                Write-Information -Tags "Audit" -MessageData $log
            }
            elseif (($ex.CategoryInfo.Reason -eq 'ManagementObjectNotFoundException') -and ($ex.Exception.Message -like "*$($group.id)*")) {
                # Send auditlog to HelloID   
                $Log = @{
                    Action            = "RevokeMembership" # optional. ENUM (undefined = default) 
                    System            = "ExchangeOnline" # optional (free format text) 
                    Message           = "Skipped $($actionMessage). Reason: Group not found." # required (free format text) 
                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                    TargetDisplayName = $group.displayName # optional (free format text)
                    TargetIdentifier  = $group.id # optional (free format text)
                }
                Write-Information -Tags "Audit" -MessageData $log
            }
            elseif (($ex.CategoryInfo.Reason -eq 'ManagementObjectNotFoundException') -and ($ex.Exception.Message -like "*$($userToRemove.id)*")) {
                # Send auditlog to HelloID
                $Log = @{
                    Action            = "RevokeMembership" # optional. ENUM (undefined = default) 
                    System            = "ExchangeOnline" # optional (free format text) 
                    Message           = "Skipped $($actionMessage). Reason: User not found." # required (free format text) 
                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                    TargetDisplayName = $group.displayName # optional (free format text)
                    TargetIdentifier  = $group.id # optional (free format text)
                }
                Write-Information -Tags "Audit" -MessageData $log
            }
            else {
                # Send auditlog to HelloID   
                $Log = @{
                    Action            = "RevokeMembership" # optional. ENUM (undefined = default) 
                    System            = "ExchangeOnline" # optional (free format text) 
                    Message           = $auditMessage # required (free format text) 
                    IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                    TargetDisplayName = $group.displayName # optional (free format text)
                    TargetIdentifier  = $group.id # optional (free format text)
                }
                Write-Information -Tags "Audit" -MessageData $log
                Write-Warning $warningMessage
                Write-Error $auditMessage
            }
        }
    }
}
catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)"
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }

    $Log = @{
        # Action            = "" # optional. ENUM (undefined = default) 
        System            = "ExchangeOnline" # optional (free format text) 
        Message           = $auditMessage # required (free format text) 
        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = $mailbox.DisplayName # optional (free format text)
        TargetIdentifier  = $([string]$mailbox.Guid) # optional (free format text)
    }
    
    Write-Information -Tags "Audit" -MessageData $log
    Write-Warning $warningMessage
    Write-Error $auditMessage
}
finally {
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/disconnect-exchangeonline?view=exchange-ps
    $deleteExchangeSessionSplatParams = @{
        Confirm     = $false
        ErrorAction = "Stop"
    }
    $null = Disconnect-ExchangeOnline @deleteExchangeSessionSplatParams
}
