# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#HelloID variables
#Note: when running this script inside HelloID; portalUrl and API credentials are provided automatically (generate and save API credentials first in your admin panel!)
$portalUrl = "https://CUSTOMER.helloid.com"
$apiKey = "API_KEY"
$apiSecret = "API_SECRET"
$delegatedFormAccessGroupNames = @("") #Only unique names are supported. Groups must exist!
$delegatedFormCategories = @("") #Only unique names are supported. Categories will be created if not exists
$script:debugLogging = $false #Default value: $false. If $true, the HelloID resource GUIDs will be shown in the logging
$script:duplicateForm = $false #Default value: $false. If $true, the HelloID resource names will be changed to import a duplicate Form
$script:duplicateFormSuffix = "_tmp" #the suffix will be added to all HelloID resource names to generate a duplicate form with different resource names

#The following HelloID Global variables are used by this form. No existing HelloID global variables will be overriden only new ones are created.
#NOTE: You can also update the HelloID Global variable values afterwards in the HelloID Admin Portal: https://<CUSTOMER>.helloid.com/admin/variablelibrary
$globalHelloIDVariables = [System.Collections.Generic.List[object]]@();

#Global variable #1 >> AADExchangeAppID
$tmpName = @'
AADExchangeAppID
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #2 >> AADExchangeCertificateThumbprint
$tmpName = @'
AADExchangeCertificateThumbprint
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});

#Global variable #3 >> AADExchangeOrganization
$tmpName = @'
AADExchangeOrganization
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False"});


#make sure write-information logging is visual
$InformationPreference = "continue"

# Check for prefilled API Authorization header
if (-not [string]::IsNullOrEmpty($portalApiBasic)) {
    $script:headers = @{"authorization" = $portalApiBasic}
    Write-Information "Using prefilled API credentials"
} else {
    # Create authorization headers with HelloID API key
    $pair = "$apiKey" + ":" + "$apiSecret"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $key = "Basic $base64"
    $script:headers = @{"authorization" = $Key}
    Write-Information "Using manual API credentials"
}

# Check for prefilled PortalBaseURL
if (-not [string]::IsNullOrEmpty($portalBaseUrl)) {
    $script:PortalBaseUrl = $portalBaseUrl
    Write-Information "Using prefilled PortalURL: $script:PortalBaseUrl"
} else {
    $script:PortalBaseUrl = $portalUrl
    Write-Information "Using manual PortalURL: $script:PortalBaseUrl"
}

# Define specific endpoint URI
$script:PortalBaseUrl = $script:PortalBaseUrl.trim("/") + "/"  

# Make sure to reveive an empty array using PowerShell Core
function ConvertFrom-Json-WithEmptyArray([string]$jsonString) {
    # Running in PowerShell Core?
    if($IsCoreCLR -eq $true){
        $r = [Object[]]($jsonString | ConvertFrom-Json -NoEnumerate)
        return ,$r  # Force return value to be an array using a comma
    } else {
        $r = [Object[]]($jsonString | ConvertFrom-Json)
        return ,$r  # Force return value to be an array using a comma
    }
}

function Invoke-HelloIDGlobalVariable {
    param(
        [parameter(Mandatory)][String]$Name,
        [parameter(Mandatory)][String][AllowEmptyString()]$Value,
        [parameter(Mandatory)][String]$Secret
    )

    $Name = $Name + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/automation/variables/named/$Name")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
    
        if ([string]::IsNullOrEmpty($response.automationVariableGuid)) {
            #Create Variable
            $body = @{
                name     = $Name;
                value    = $Value;
                secret   = $Secret;
                ItemType = 0;
            }    
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl + "api/v1/automation/variable")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $variableGuid = $response.automationVariableGuid

            Write-Information "Variable '$Name' created$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        } else {
            $variableGuid = $response.automationVariableGuid
            Write-Warning "Variable '$Name' already exists$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        }
    } catch {
        Write-Error "Variable '$Name', message: $_"
    }
}

function Invoke-HelloIDAutomationTask {
    param(
        [parameter(Mandatory)][String]$TaskName,
        [parameter(Mandatory)][String]$UseTemplate,
        [parameter(Mandatory)][String]$AutomationContainer,
        [parameter(Mandatory)][String][AllowEmptyString()]$Variables,
        [parameter(Mandatory)][String]$PowershellScript,
        [parameter()][String][AllowEmptyString()]$ObjectGuid,
        [parameter()][String][AllowEmptyString()]$ForceCreateTask,
        [parameter(Mandatory)][Ref]$returnObject
    )
    
    $TaskName = $TaskName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl +"api/v1/automationtasks?search=$TaskName&container=$AutomationContainer")
        $responseRaw = (Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false) 
        $response = $responseRaw | Where-Object -filter {$_.name -eq $TaskName}
    
        if([string]::IsNullOrEmpty($response.automationTaskGuid) -or $ForceCreateTask -eq $true) {
            #Create Task

            $body = @{
                name                = $TaskName;
                useTemplate         = $UseTemplate;
                powerShellScript    = $PowershellScript;
                automationContainer = $AutomationContainer;
                objectGuid          = $ObjectGuid;
                variables           = (ConvertFrom-Json-WithEmptyArray($Variables));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl +"api/v1/automationtasks/powershell")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $taskGuid = $response.automationTaskGuid

            Write-Information "Powershell task '$TaskName' created$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        } else {
            #Get TaskGUID
            $taskGuid = $response.automationTaskGuid
            Write-Warning "Powershell task '$TaskName' already exists$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        }
    } catch {
        Write-Error "Powershell task '$TaskName', message: $_"
    }

    $returnObject.Value = $taskGuid
}

function Invoke-HelloIDDatasource {
    param(
        [parameter(Mandatory)][String]$DatasourceName,
        [parameter(Mandatory)][String]$DatasourceType,
        [parameter(Mandatory)][String][AllowEmptyString()]$DatasourceModel,
        [parameter()][String][AllowEmptyString()]$DatasourceStaticValue,
        [parameter()][String][AllowEmptyString()]$DatasourcePsScript,        
        [parameter()][String][AllowEmptyString()]$DatasourceInput,
        [parameter()][String][AllowEmptyString()]$AutomationTaskGuid,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $DatasourceName = $DatasourceName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    $datasourceTypeName = switch($DatasourceType) { 
        "1" { "Native data source"; break} 
        "2" { "Static data source"; break} 
        "3" { "Task data source"; break} 
        "4" { "Powershell data source"; break}
    }
    
    try {
        $uri = ($script:PortalBaseUrl +"api/v1/datasource/named/$DatasourceName")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
      
        if([string]::IsNullOrEmpty($response.dataSourceGUID)) {
            #Create DataSource
            $body = @{
                name               = $DatasourceName;
                type               = $DatasourceType;
                model              = (ConvertFrom-Json-WithEmptyArray($DatasourceModel));
                automationTaskGUID = $AutomationTaskGuid;
                value              = (ConvertFrom-Json-WithEmptyArray($DatasourceStaticValue));
                script             = $DatasourcePsScript;
                input              = (ConvertFrom-Json-WithEmptyArray($DatasourceInput));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
      
            $uri = ($script:PortalBaseUrl +"api/v1/datasource")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
              
            $datasourceGuid = $response.dataSourceGUID
            Write-Information "$datasourceTypeName '$DatasourceName' created$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        } else {
            #Get DatasourceGUID
            $datasourceGuid = $response.dataSourceGUID
            Write-Warning "$datasourceTypeName '$DatasourceName' already exists$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        }
    } catch {
      Write-Error "$datasourceTypeName '$DatasourceName', message: $_"
    }

    $returnObject.Value = $datasourceGuid
}

function Invoke-HelloIDDynamicForm {
    param(
        [parameter(Mandatory)][String]$FormName,
        [parameter(Mandatory)][String]$FormSchema,
        [parameter(Mandatory)][Ref]$returnObject
    )
    
    $FormName = $FormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/forms/$FormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        } catch {
            $response = $null
        }
    
        if(([string]::IsNullOrEmpty($response.dynamicFormGUID)) -or ($response.isUpdated -eq $true)) {
            #Create Dynamic form
            $body = @{
                Name       = $FormName;
                FormSchema = (ConvertFrom-Json-WithEmptyArray($FormSchema));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl +"api/v1/forms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
    
            $formGuid = $response.dynamicFormGUID
            Write-Information "Dynamic form '$formName' created$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        } else {
            $formGuid = $response.dynamicFormGUID
            Write-Warning "Dynamic form '$FormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        }
    } catch {
        Write-Error "Dynamic form '$FormName', message: $_"
    }

    $returnObject.Value = $formGuid
}


function Invoke-HelloIDDelegatedForm {
    param(
        [parameter(Mandatory)][String]$DelegatedFormName,
        [parameter(Mandatory)][String]$DynamicFormGuid,
        [parameter()][Array][AllowEmptyString()]$AccessGroups,
        [parameter()][String][AllowEmptyString()]$Categories,
        [parameter(Mandatory)][String]$UseFaIcon,
        [parameter()][String][AllowEmptyString()]$FaIcon,
        [parameter()][String][AllowEmptyString()]$task,
        [parameter(Mandatory)][Ref]$returnObject
    )
    $delegatedFormCreated = $false
    $DelegatedFormName = $DelegatedFormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms/$DelegatedFormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        } catch {
            $response = $null
        }
    
        if([string]::IsNullOrEmpty($response.delegatedFormGUID)) {
            #Create DelegatedForm
            $body = @{
                name            = $DelegatedFormName;
                dynamicFormGUID = $DynamicFormGuid;
                isEnabled       = "True";
                useFaIcon       = $UseFaIcon;
                faIcon          = $FaIcon;
                task            = ConvertFrom-Json -inputObject $task;
            }
            if(-not[String]::IsNullOrEmpty($AccessGroups)) { 
                $body += @{
                    accessGroups    = (ConvertFrom-Json-WithEmptyArray($AccessGroups));
                }
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
    
            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Information "Delegated form '$DelegatedFormName' created$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
            $delegatedFormCreated = $true

            $bodyCategories = $Categories
            $uri = ($script:PortalBaseUrl +"api/v1/delegatedforms/$delegatedFormGuid/categories")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $bodyCategories
            Write-Information "Delegated form '$DelegatedFormName' updated with categories"
        } else {
            #Get delegatedFormGUID
            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Warning "Delegated form '$DelegatedFormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
        }
    } catch {
        Write-Error "Delegated form '$DelegatedFormName', message: $_"
    }

    $returnObject.value.guid = $delegatedFormGuid
    $returnObject.value.created = $delegatedFormCreated
}


<# Begin: HelloID Global Variables #>
foreach ($item in $globalHelloIDVariables) {
	Invoke-HelloIDGlobalVariable -Name $item.name -Value $item.value -Secret $item.secret 
}
<# End: HelloID Global Variables #>


<# Begin: HelloID Data sources #>
<# Begin: DataSource "Exchange-Online-group-generate-table-wildcard v2" #>
$tmpPsScript = @'
# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Used to connect to Exchange Online in an unattended scripting scenario using a certificate.
# Follow the Microsoft Docs on how to set up the Azure App Registration: https://docs.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps
$AzureADExchangeOrganization = $AADExchangeOrganization
$AzureADExchangeAppID = $AADExchangeAppID
$AzureADExchangeCertificateThumbprint = $AADExchangeCertificateThumbprint # Certificate has to be locally installed

# PowerShell commands to import
$commands = @(
    "Get-User" # Always required
    , "Get-Group"
    , "Get-DistributionGroup"
)

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$ErrorObject
    )

    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }

        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $response = $ErrorObject.Exception.Response
            if ($response -is [System.Net.HttpWebResponse]) {
                $httpErrorObj.ErrorMessage = $response.StatusDescription
            }
            else {
                $httpErrorObj.ErrorMessage = $ErrorObject.Exception.Message
            }
        }
        else {
            $httpErrorObj.ErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $httpErrorObj
    }
}
#endregion functions

# Import module
$moduleName = "ExchangeOnlineManagement"

# If module is imported say that and do nothing
if (Get-Module | Where-Object { $_.Name -eq $ModuleName }) {
    Write-Verbose "Module $ModuleName is already imported."
}
else {
    # If module is not imported, but available on disk then import
    if (Get-Module -ListAvailable | Where-Object { $_.Name -eq $ModuleName }) {
        $module = Import-Module $ModuleName -Cmdlet $commands
        Write-Verbose "Imported module $ModuleName"
    }
    else {
        # If the module is not imported, not available and not in the online gallery then abort
        throw "Module $ModuleName not imported, not available. Please install the module using: Install-Module -Name $ModuleName -Force"
    }
}

# Connect to Exchange
try {
    Write-Verbose "Connecting to Exchange Online"

    # Connect to Exchange Online in an unattended scripting scenario using a certificate thumbprint (certificate has to be locally installed).
    $exchangeSessionParams = @{
        Organization          = $AzureADExchangeOrganization
        AppID                 = $AzureADExchangeAppID
        CertificateThumbPrint = $AzureADExchangeCertificateThumbprint
        CommandName           = $commands
        ShowBanner            = $false
        ShowProgress          = $false
        TrackPerformance      = $false
        ErrorAction           = 'Stop'
    }

    $exchangeSession = Connect-ExchangeOnline @exchangeSessionParams
    
    Write-Information "Successfully connected to Exchange Online"
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
    throw "Error connecting to Exchange Online. Error Message: $auditErrorMessage"
}

try {
    $searchValue = $datasource.searchValue

    if ([String]::IsNullOrEmpty($searchValue) -eq $true) {
        # Do nothing
    }
    else { 
        $searchFilter = "displayName -like '*$searchValue*'"
        Write-Verbose "Querying Exchange Online groups with Filter '$($searchFilter)'"

        $exchangeOnlineGroups = Get-Group -Filter $searchFilter

        $groups = $exchangeOnlineGroups
        $resultCount = $groups.id.Count
     
        Write-Information "Successfully queried Exchange Online groups with Filter '$($searchFilter)'. Result count: $resultCount"
     
        if ($resultCount -gt 0) {
            foreach ($group in $groups) {
                $returnObject = @{
                    name        = "$($group.displayName)";
                    id          = "$($group.id)";
                    description = "$($group.description)";
                    groupType   = "$($group.GroupType)"
                }
                Write-Output $returnObject
            }
        }
    }
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
    throw "Error searching for Exchange Online groups with Filter '$($searchFilter)'. Error Message: $auditErrorMessage"
}
finally {
    Write-Verbose "Disconnection from Exchange Online"
    $exchangeSessionEnd = Disconnect-ExchangeOnline -Confirm:$false -Verbose:$false -ErrorAction Stop    
    Write-Information "Successfully disconnected from Exchange Online"
}
'@ 
$tmpModel = @'
[{"key":"description","type":0},{"key":"groupType","type":0},{"key":"name","type":0},{"key":"id","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"searchValue","type":0,"options":1}]
'@ 
$dataSourceGuid_0 = [PSCustomObject]@{} 
$dataSourceGuid_0_Name = @'
Exchange-Online-group-generate-table-wildcard v2
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_0_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -returnObject ([Ref]$dataSourceGuid_0) 
<# End: DataSource "Exchange-Online-group-generate-table-wildcard v2" #>

<# Begin: DataSource "Exchange-Online-group-generate-table-owners v2" #>
$tmpPsScript = @'
# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Used to connect to Exchange Online in an unattended scripting scenario using a certificate.
# Follow the Microsoft Docs on how to set up the Azure App Registration: https://docs.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps
$AzureADExchangeOrganization = $AADExchangeOrganization
$AzureADExchangeAppID = $AADExchangeAppID
$AzureADExchangeCertificateThumbprint = $AADExchangeCertificateThumbprint # Certificate has to be locally installed

# PowerShell commands to import
$commands = @(
    "Get-User" # Always required
    , "Get-DistributionGroup"
)

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$ErrorObject
    )

    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }

        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $response = $ErrorObject.Exception.Response
            if ($response -is [System.Net.HttpWebResponse]) {
                $httpErrorObj.ErrorMessage = $response.StatusDescription
            }
            else {
                $httpErrorObj.ErrorMessage = $ErrorObject.Exception.Message
            }
        }
        else {
            $httpErrorObj.ErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $httpErrorObj
    }
}
#endregion functions

# Import module
$moduleName = "ExchangeOnlineManagement"

# If module is imported say that and do nothing
if (Get-Module | Where-Object { $_.Name -eq $ModuleName }) {
    Write-Verbose "Module $ModuleName is already imported."
}
else {
    # If module is not imported, but available on disk then import
    if (Get-Module -ListAvailable | Where-Object { $_.Name -eq $ModuleName }) {
        $module = Import-Module $ModuleName -Cmdlet $commands
        Write-Verbose "Imported module $ModuleName"
    }
    else {
        # If the module is not imported, not available and not in the online gallery then abort
        throw "Module $ModuleName not imported, not available. Please install the module using: Install-Module -Name $ModuleName -Force"
    }
}

# Connect to Exchange
try {
    Write-Verbose "Connecting to Exchange Online"

    # Connect to Exchange Online in an unattended scripting scenario using a certificate thumbprint (certificate has to be locally installed).
    $exchangeSessionParams = @{
        Organization          = $AzureADExchangeOrganization
        AppID                 = $AzureADExchangeAppID
        CertificateThumbPrint = $AzureADExchangeCertificateThumbprint
        CommandName           = $commands
        ShowBanner            = $false
        ShowProgress          = $false
        TrackPerformance      = $false
        ErrorAction           = 'Stop'
    }

    $exchangeSession = Connect-ExchangeOnline @exchangeSessionParams
    
    Write-Information "Successfully connected to Exchange Online"
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
    throw "Error connecting to Exchange Online. Error Message: $auditErrorMessage"
}

try {
    $groupIdentity = $datasource.selectedGroup.id

    if ([String]::IsNullOrEmpty($groupIdentity) -eq $true) {
        Write-Error "No Group id provided"
    }
    else { 
        Write-Verbose "Querying Exchange Online group owners"
        
        $exchangeOnlineGroupOwners = (Get-DistributionGroup -Identity $groupIdentity).managedBy
        $exchangeOnlineUsers = foreach ($exchangeOnlineGroupOwner in $exchangeOnlineGroupOwners) {
            Get-User $exchangeOnlineGroupOwner
        }
        $users = $exchangeOnlineUsers
        $resultCount = $users.id.Count
        
        Write-Information "Successfully queried Exchange Online group owners. Result count: $resultCount"
         
        if ($resultCount -gt 0) {
            foreach ($user in $users) {
                $displayValue = $user.displayName + " [" + $user.WindowsLiveID + "]"
                  
                $returnObject = @{
                    Name              = $displayValue;
                    UserPrincipalName = "$($user.UserPrincipalName)";
                    Id                = "$($user.id)";
                }
                Write-Output $returnObject
            }
        }
    }
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
    throw "Error searching for Exchange Online group owners. Error Message: $auditErrorMessage"
}
finally {
    Write-Verbose "Disconnection from Exchange Online"
    $exchangeSessionEnd = Disconnect-ExchangeOnline -Confirm:$false -Verbose:$false -ErrorAction Stop    
    Write-Information "Successfully disconnected from Exchange Online"
}
'@ 
$tmpModel = @'
[{"key":"Name","type":0},{"key":"UserPrincipalName","type":0},{"key":"Id","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"selectedGroup","type":0,"options":1}]
'@ 
$dataSourceGuid_2 = [PSCustomObject]@{} 
$dataSourceGuid_2_Name = @'
Exchange-Online-group-generate-table-owners v2
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_2_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -returnObject ([Ref]$dataSourceGuid_2) 
<# End: DataSource "Exchange-Online-group-generate-table-owners v2" #>

<# Begin: DataSource "Exchange-online-user-generate-table v2" #>
$tmpPsScript = @'
# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Used to connect to Exchange Online in an unattended scripting scenario using a certificate.
# Follow the Microsoft Docs on how to set up the Azure App Registration: https://docs.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps
$AzureADExchangeOrganization = $AADExchangeOrganization
$AzureADExchangeAppID = $AADExchangeAppID
$AzureADExchangeCertificateThumbprint = $AADExchangeCertificateThumbprint # Certificate has to be locally installed

# PowerShell commands to import
$commands = @(
    "Get-User" # Always required
)

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$ErrorObject
    )

    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }

        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $response = $ErrorObject.Exception.Response
            if ($response -is [System.Net.HttpWebResponse]) {
                $httpErrorObj.ErrorMessage = $response.StatusDescription
            }
            else {
                $httpErrorObj.ErrorMessage = $ErrorObject.Exception.Message
            }
        }
        else {
            $httpErrorObj.ErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $httpErrorObj
    }
}
#endregion functions

# Import module
$moduleName = "ExchangeOnlineManagement"

# If module is imported say that and do nothing
if (Get-Module | Where-Object { $_.Name -eq $ModuleName }) {
    Write-Verbose "Module $ModuleName is already imported."
}
else {
    # If module is not imported, but available on disk then import
    if (Get-Module -ListAvailable | Where-Object { $_.Name -eq $ModuleName }) {
        $module = Import-Module $ModuleName -Cmdlet $commands
        Write-Verbose "Imported module $ModuleName"
    }
    else {
        # If the module is not imported, not available and not in the online gallery then abort
        throw "Module $ModuleName not imported, not available. Please install the module using: Install-Module -Name $ModuleName -Force"
    }
}

# Connect to Exchange
try {
    Write-Verbose "Connecting to Exchange Online"

    # Connect to Exchange Online in an unattended scripting scenario using a certificate thumbprint (certificate has to be locally installed).
    $exchangeSessionParams = @{
        Organization          = $AzureADExchangeOrganization
        AppID                 = $AzureADExchangeAppID
        CertificateThumbPrint = $AzureADExchangeCertificateThumbprint
        CommandName           = $commands
        ShowBanner            = $false
        ShowProgress          = $false
        TrackPerformance      = $false
        ErrorAction           = 'Stop'
    }

    $exchangeSession = Connect-ExchangeOnline @exchangeSessionParams
    
    Write-Information "Successfully connected to Exchange Online"
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
    throw "Error connecting to Exchange Online. Error Message: $auditErrorMessage"
}

try {
    Write-Verbose "Querying Exchange Online users"
    
    $exchangeOnlineUsers = Get-User -ResultSize Unlimited
    $users = $exchangeOnlineUsers
    $resultCount = $users.id.Count

    Write-Information "Successfully queried Exchange Online users. Result count: $resultCount"
        
    if ($resultCount -gt 0) {
        foreach ($user in $users) {
            $displayValue = $user.displayName + " [" + $user.WindowsLiveID + "]"
                
            $returnObject = @{
                Name              = $displayValue;
                UserPrincipalName = "$($user.UserPrincipalName)";
                Id                = "$($user.id)";
            }
            Write-Output $returnObject
        }
    }
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
    throw "Error searching for Exchange Online users. Error Message: $auditErrorMessage"
}
finally {
    Write-Verbose "Disconnection from Exchange Online"
    $exchangeSessionEnd = Disconnect-ExchangeOnline -Confirm:$false -Verbose:$false -ErrorAction Stop    
    Write-Information "Successfully disconnected from Exchange Online"
}
'@ 
$tmpModel = @'
[{"key":"Name","type":0},{"key":"UserPrincipalName","type":0},{"key":"Id","type":0}]
'@ 
$tmpInput = @'
[]
'@ 
$dataSourceGuid_1 = [PSCustomObject]@{} 
$dataSourceGuid_1_Name = @'
Exchange-online-user-generate-table v2
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_1_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -returnObject ([Ref]$dataSourceGuid_1) 
<# End: DataSource "Exchange-online-user-generate-table v2" #>

<# Begin: DataSource "Exchange-Online-group-generate-table-members v2" #>
$tmpPsScript = @'
# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Used to connect to Exchange Online in an unattended scripting scenario using a certificate.
# Follow the Microsoft Docs on how to set up the Azure App Registration: https://docs.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps
$AzureADExchangeOrganization = $AADExchangeOrganization
$AzureADExchangeAppID = $AADExchangeAppID
$AzureADExchangeCertificateThumbprint = $AADExchangeCertificateThumbprint # Certificate has to be locally installed

# PowerShell commands to import
$commands = @(
    "Get-User" # Always required
    , "Get-DistributionGroupMember"
)

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$ErrorObject
    )

    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }

        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $response = $ErrorObject.Exception.Response
            if ($response -is [System.Net.HttpWebResponse]) {
                $httpErrorObj.ErrorMessage = $response.StatusDescription
            }
            else {
                $httpErrorObj.ErrorMessage = $ErrorObject.Exception.Message
            }
        }
        else {
            $httpErrorObj.ErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $httpErrorObj
    }
}
#endregion functions

# Import module
$moduleName = "ExchangeOnlineManagement"

# If module is imported say that and do nothing
if (Get-Module | Where-Object { $_.Name -eq $ModuleName }) {
    Write-Verbose "Module $ModuleName is already imported."
}
else {
    # If module is not imported, but available on disk then import
    if (Get-Module -ListAvailable | Where-Object { $_.Name -eq $ModuleName }) {
        $module = Import-Module $ModuleName -Cmdlet $commands
        Write-Verbose "Imported module $ModuleName"
    }
    else {
        # If the module is not imported, not available and not in the online gallery then abort
        throw "Module $ModuleName not imported, not available. Please install the module using: Install-Module -Name $ModuleName -Force"
    }
}

# Connect to Exchange
try {
    Write-Verbose "Connecting to Exchange Online"

    # Connect to Exchange Online in an unattended scripting scenario using a certificate thumbprint (certificate has to be locally installed).
    $exchangeSessionParams = @{
        Organization          = $AzureADExchangeOrganization
        AppID                 = $AzureADExchangeAppID
        CertificateThumbPrint = $AzureADExchangeCertificateThumbprint
        CommandName           = $commands
        ShowBanner            = $false
        ShowProgress          = $false
        TrackPerformance      = $false
        ErrorAction           = 'Stop'
    }

    $exchangeSession = Connect-ExchangeOnline @exchangeSessionParams
    
    Write-Information "Successfully connected to Exchange Online"
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
    throw "Error connecting to Exchange Online. Error Message: $auditErrorMessage"
}

try {
    $groupIdentity = $datasource.selectedGroup.id

    if ([String]::IsNullOrEmpty($groupIdentity) -eq $true) {
        Write-Error "No Group id provided"
    }
    else { 
        Write-Verbose "Querying Exchange Online group members"
        
        $exchangeOnlineUsers = Get-DistributionGroupMember -Identity $groupIdentity
        $users = $exchangeOnlineUsers
        $resultCount = $users.id.Count
        
        Write-Information "Successfully queried Exchange Online group members. Result count: $resultCount"
         
        if ($resultCount -gt 0) {
            foreach ($user in $users) {
                $displayValue = $user.displayName + " [" + $user.WindowsLiveID + "]"
                  
                $returnObject = @{
                    Name              = $displayValue;
                    UserPrincipalName = "$($user.UserPrincipalName)";
                    Id                = "$($user.id)";
                }
                Write-Output $returnObject
            }
        }
    }
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
    throw "Error searching for Exchange Online group members. Error Message: $auditErrorMessage"
}
finally {
    Write-Verbose "Disconnection from Exchange Online"
    $exchangeSessionEnd = Disconnect-ExchangeOnline -Confirm:$false -Verbose:$false -ErrorAction Stop    
    Write-Information "Successfully disconnected from Exchange Online"
}
'@ 
$tmpModel = @'
[{"key":"Name","type":0},{"key":"UserPrincipalName","type":0},{"key":"Id","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"selectedGroup","type":0,"options":1}]
'@ 
$dataSourceGuid_4 = [PSCustomObject]@{} 
$dataSourceGuid_4_Name = @'
Exchange-Online-group-generate-table-members v2
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_4_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -returnObject ([Ref]$dataSourceGuid_4) 
<# End: DataSource "Exchange-Online-group-generate-table-members v2" #>

<# Begin: DataSource "Exchange-online-user-generate-table v2" #>
$tmpPsScript = @'
# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Used to connect to Exchange Online in an unattended scripting scenario using a certificate.
# Follow the Microsoft Docs on how to set up the Azure App Registration: https://docs.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps
$AzureADExchangeOrganization = $AADExchangeOrganization
$AzureADExchangeAppID = $AADExchangeAppID
$AzureADExchangeCertificateThumbprint = $AADExchangeCertificateThumbprint # Certificate has to be locally installed

# PowerShell commands to import
$commands = @(
    "Get-User" # Always required
)

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$ErrorObject
    )

    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }

        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $response = $ErrorObject.Exception.Response
            if ($response -is [System.Net.HttpWebResponse]) {
                $httpErrorObj.ErrorMessage = $response.StatusDescription
            }
            else {
                $httpErrorObj.ErrorMessage = $ErrorObject.Exception.Message
            }
        }
        else {
            $httpErrorObj.ErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $httpErrorObj
    }
}
#endregion functions

# Import module
$moduleName = "ExchangeOnlineManagement"

# If module is imported say that and do nothing
if (Get-Module | Where-Object { $_.Name -eq $ModuleName }) {
    Write-Verbose "Module $ModuleName is already imported."
}
else {
    # If module is not imported, but available on disk then import
    if (Get-Module -ListAvailable | Where-Object { $_.Name -eq $ModuleName }) {
        $module = Import-Module $ModuleName -Cmdlet $commands
        Write-Verbose "Imported module $ModuleName"
    }
    else {
        # If the module is not imported, not available and not in the online gallery then abort
        throw "Module $ModuleName not imported, not available. Please install the module using: Install-Module -Name $ModuleName -Force"
    }
}

# Connect to Exchange
try {
    Write-Verbose "Connecting to Exchange Online"

    # Connect to Exchange Online in an unattended scripting scenario using a certificate thumbprint (certificate has to be locally installed).
    $exchangeSessionParams = @{
        Organization          = $AzureADExchangeOrganization
        AppID                 = $AzureADExchangeAppID
        CertificateThumbPrint = $AzureADExchangeCertificateThumbprint
        CommandName           = $commands
        ShowBanner            = $false
        ShowProgress          = $false
        TrackPerformance      = $false
        ErrorAction           = 'Stop'
    }

    $exchangeSession = Connect-ExchangeOnline @exchangeSessionParams
    
    Write-Information "Successfully connected to Exchange Online"
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
    throw "Error connecting to Exchange Online. Error Message: $auditErrorMessage"
}

try {
    Write-Verbose "Querying Exchange Online users"
    
    $exchangeOnlineUsers = Get-User -ResultSize Unlimited
    $users = $exchangeOnlineUsers
    $resultCount = $users.id.Count

    Write-Information "Successfully queried Exchange Online users. Result count: $resultCount"
        
    if ($resultCount -gt 0) {
        foreach ($user in $users) {
            $displayValue = $user.displayName + " [" + $user.WindowsLiveID + "]"
                
            $returnObject = @{
                Name              = $displayValue;
                UserPrincipalName = "$($user.UserPrincipalName)";
                Id                = "$($user.id)";
            }
            Write-Output $returnObject
        }
    }
}
catch {
    $ex = $PSItem
    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObject = Resolve-HTTPError -Error $ex

        $verboseErrorMessage = $errorObject.ErrorMessage

        $auditErrorMessage = $errorObject.ErrorMessage
    }

    # If error message empty, fall back on $ex.Exception.Message
    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {
        $verboseErrorMessage = $ex.Exception.Message
    }
    if ([String]::IsNullOrEmpty($auditErrorMessage)) {
        $auditErrorMessage = $ex.Exception.Message
    }

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)"
    throw "Error searching for Exchange Online users. Error Message: $auditErrorMessage"
}
finally {
    Write-Verbose "Disconnection from Exchange Online"
    $exchangeSessionEnd = Disconnect-ExchangeOnline -Confirm:$false -Verbose:$false -ErrorAction Stop    
    Write-Information "Successfully disconnected from Exchange Online"
}
'@ 
$tmpModel = @'
[{"key":"Name","type":0},{"key":"UserPrincipalName","type":0},{"key":"Id","type":0}]
'@ 
$tmpInput = @'
[]
'@ 
$dataSourceGuid_3 = [PSCustomObject]@{} 
$dataSourceGuid_3_Name = @'
Exchange-online-user-generate-table v2
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_3_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -returnObject ([Ref]$dataSourceGuid_3) 
<# End: DataSource "Exchange-online-user-generate-table v2" #>
<# End: HelloID Data sources #>

<# Begin: Dynamic Form "Exchange Online - Group - Manage memberships" #>
$tmpSchema = @"
[{"label":"Select group","fields":[{"key":"searchfield","templateOptions":{"label":"Search","placeholder":""},"type":"input","summaryVisibility":"Hide element","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"gridGroups","templateOptions":{"label":"Select group","required":true,"grid":{"columns":[{"headerName":"Name","field":"name"},{"headerName":"Description","field":"description"},{"headerName":"Group Type","field":"groupType"},{"headerName":"Id","field":"id"}],"height":300,"rowSelection":"single"},"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_0","input":{"propertyInputs":[{"propertyName":"searchValue","otherFieldValue":{"otherFieldKey":"searchfield"}}]}},"useFilter":false},"type":"grid","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":true}]},{"label":"Members","fields":[{"key":"owners","templateOptions":{"label":"Manage group owners","required":false,"filterable":true,"useDataSource":true,"dualList":{"options":[{"guid":"75ea2890-88f8-4851-b202-626123054e14","Name":"Apple"},{"guid":"0607270d-83e2-4574-9894-0b70011b663f","Name":"Pear"},{"guid":"1ef6fe01-3095-4614-a6db-7c8cd416ae3b","Name":"Orange"}],"optionKeyProperty":"Name","optionDisplayProperty":"Name","labelLeft":"Available","labelRight":"Owners"},"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_1","input":{"propertyInputs":[]}},"destinationDataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_2","input":{"propertyInputs":[{"propertyName":"selectedGroup","otherFieldValue":{"otherFieldKey":"gridGroups"}}]}}},"type":"duallist","summaryVisibility":"Show","sourceDataSourceIdentifierSuffix":"source-datasource","destinationDataSourceIdentifierSuffix":"destination-datasource","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"members","templateOptions":{"label":"Manage group memberships","required":false,"filterable":true,"useDataSource":true,"dualList":{"options":[{"guid":"75ea2890-88f8-4851-b202-626123054e14","Name":"Apple"},{"guid":"0607270d-83e2-4574-9894-0b70011b663f","Name":"Pear"},{"guid":"1ef6fe01-3095-4614-a6db-7c8cd416ae3b","Name":"Orange"}],"optionKeyProperty":"Name","optionDisplayProperty":"Name","labelLeft":"Available","labelRight":"Member of"},"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_3","input":{"propertyInputs":[]}},"destinationDataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_4","input":{"propertyInputs":[{"propertyName":"selectedGroup","otherFieldValue":{"otherFieldKey":"gridGroups"}}]}},"useFilter":false},"type":"duallist","summaryVisibility":"Show","sourceDataSourceIdentifierSuffix":"source-datasource","destinationDataSourceIdentifierSuffix":"destination-datasource","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}]}]
"@ 

$dynamicFormGuid = [PSCustomObject]@{} 
$dynamicFormName = @'
Exchange Online - Group - Manage memberships
'@ 
Invoke-HelloIDDynamicForm -FormName $dynamicFormName -FormSchema $tmpSchema  -returnObject ([Ref]$dynamicFormGuid) 
<# END: Dynamic Form #>

<# Begin: Delegated Form Access Groups and Categories #>
$delegatedFormAccessGroupGuids = @()
if(-not[String]::IsNullOrEmpty($delegatedFormAccessGroupNames)){
    foreach($group in $delegatedFormAccessGroupNames) {
        try {
            $uri = ($script:PortalBaseUrl +"api/v1/groups/$group")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
            $delegatedFormAccessGroupGuid = $response.groupGuid
            $delegatedFormAccessGroupGuids += $delegatedFormAccessGroupGuid
            
            Write-Information "HelloID (access)group '$group' successfully found$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormAccessGroupGuid })"
        } catch {
            Write-Error "HelloID (access)group '$group', message: $_"
        }
    }
    if($null -ne $delegatedFormAccessGroupGuids){
        $delegatedFormAccessGroupGuids = ($delegatedFormAccessGroupGuids | Select-Object -Unique | ConvertTo-Json -Depth 100 -Compress)
    }
}

$delegatedFormCategoryGuids = @()
foreach($category in $delegatedFormCategories) {
    try {
        $uri = ($script:PortalBaseUrl +"api/v1/delegatedformcategories/$category")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        $response = $response | Where-Object {$_.name.en -eq $category}
        
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid
        
        Write-Information "HelloID Delegated Form category '$category' successfully found$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    } catch {
        Write-Warning "HelloID Delegated Form category '$category' not found"
        $body = @{
            name = @{"en" = $category};
        }
        $body = ConvertTo-Json -InputObject $body -Depth 100

        $uri = ($script:PortalBaseUrl +"api/v1/delegatedformcategories")
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid

        Write-Information "HelloID Delegated Form category '$category' successfully created$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    }
}
$delegatedFormCategoryGuids = (ConvertTo-Json -InputObject $delegatedFormCategoryGuids -Depth 100 -Compress)
<# End: Delegated Form Access Groups and Categories #>

<# Begin: Delegated Form #>
$delegatedFormRef = [PSCustomObject]@{guid = $null; created = $null} 
$delegatedFormName = @'
Exchange Online - Group - Manage memberships
'@
$tmpTask = @'
{"name":"Exchange Online - Group - Manage memberships","script":"# Set TLS to accept TLS, TLS 1.1 and TLS 1.2\r\n[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12\r\n\r\n$VerbosePreference = \"SilentlyContinue\"\r\n$InformationPreference = \"Continue\"\r\n$WarningPreference = \"Continue\"\r\n\r\n# Used to connect to Exchange Online in an unattended scripting scenario using a certificate.\r\n# Follow the Microsoft Docs on how to set up the Azure App Registration: https://docs.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps\r\n$AzureADExchangeOrganization = $AADExchangeOrganization\r\n$AzureADExchangeAppID = $AADExchangeAppID\r\n$AzureADExchangeCertificateThumbprint = $AADExchangeCertificateThumbprint # Certificate has to be locally installed\r\n\r\n# PowerShell commands to import\r\n$commands = @(\r\n    \"Get-User\" # Always required\r\n    , \"Get-Group\"\r\n    , \"Add-DistributionGroupMember\"\r\n    , \"Remove-DistributionGroupMember\"\r\n    , \"Set-DistributionGroup\"\r\n)\r\n\r\n# Form input\r\n$groupId = $form.gridGroups.id\r\n$Owners = $form.owners.right\r\n$usersToAdd = $form.members.leftToRight\r\n$usersToRemove = $form.members.rightToLeft\r\n\r\n#region functions\r\nfunction Resolve-HTTPError {\r\n    [CmdletBinding()]\r\n    param (\r\n        [Parameter(Mandatory,\r\n            ValueFromPipeline\r\n        )]\r\n        [object]$ErrorObject\r\n    )\r\n    process {\r\n        $httpErrorObj = [PSCustomObject]@{\r\n            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId\r\n            MyCommand             = $ErrorObject.InvocationInfo.MyCommand\r\n            RequestUri            = $ErrorObject.TargetObject.RequestUri\r\n            ScriptStackTrace      = $ErrorObject.ScriptStackTrace\r\n            ErrorMessage          = ''\r\n        }\r\n        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {\r\n            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message\r\n        }\r\n        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {\r\n            $httpErrorObj = Resolve-HTTPError -ErrorObject $_\r\n        }\r\n        Write-Output $httpErrorObj\r\n    }\r\n}\r\n#endregion functions\r\n\r\n# Import module\r\n$moduleName = \"ExchangeOnlineManagement\"\r\n\r\n# If module is imported say that and do nothing\r\nif (Get-Module | Where-Object { $_.Name -eq $ModuleName }) {\r\n    Write-Verbose \"Module $ModuleName is already imported.\"\r\n}\r\nelse {\r\n    # If module is not imported, but available on disk then import\r\n    if (Get-Module -ListAvailable | Where-Object { $_.Name -eq $ModuleName }) {\r\n        $module = Import-Module $ModuleName -Cmdlet $commands\r\n        Write-Verbose \"Imported module $ModuleName\"\r\n    }\r\n    else {\r\n        # If the module is not imported, not available and not in the online gallery then abort\r\n        throw \"Module $ModuleName not imported, not available. Please install the module using: Install-Module -Name $ModuleName -Force\"\r\n    }\r\n}\r\n\r\n# Connect to Exchange\r\ntry {\r\n    Write-Verbose \"Connecting to Exchange Online\"\r\n\r\n    # Connect to Exchange Online in an unattended scripting scenario using a certificate thumbprint (certificate has to be locally installed).\r\n    $exchangeSessionParams = @{\r\n        Organization          = $AzureADExchangeOrganization\r\n        AppID                 = $AzureADExchangeAppID\r\n        CertificateThumbPrint = $AzureADExchangeCertificateThumbprint\r\n        CommandName           = $commands\r\n        ShowBanner            = $false\r\n        ShowProgress          = $false\r\n        TrackPerformance      = $false\r\n        ErrorAction           = 'Stop'\r\n    }\r\n\r\n    $exchangeSession = Connect-ExchangeOnline @exchangeSessionParams\r\n    \r\n    Write-Information \"Successfully connected to Exchange Online\"\r\n}\r\ncatch {\r\n    $ex = $PSItem\r\n    if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {\r\n        $errorObject = Resolve-HTTPError -Error $ex\r\n\r\n        $verboseErrorMessage = $errorObject.ErrorMessage\r\n\r\n        $auditErrorMessage = $errorObject.ErrorMessage\r\n    }\r\n\r\n    # If error message empty, fall back on $ex.Exception.Message\r\n    if ([String]::IsNullOrEmpty($verboseErrorMessage)) {\r\n        $verboseErrorMessage = $ex.Exception.Message\r\n    }\r\n    if ([String]::IsNullOrEmpty($auditErrorMessage)) {\r\n        $auditErrorMessage = $ex.Exception.Message\r\n    }\r\n\r\n    Write-Verbose \"Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)\"\r\n    $Log = @{\r\n        Action            = \"Undefined\" # optional. ENUM (undefined = default) \r\n        System            = \"Exchange Online\" # optional (free format text) \r\n        Message           = \"Failed to connect to Exchange Online\" # required (free format text) \r\n        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = \"Exchange Online\" # optional (free format text) \r\n        \r\n    }\r\n    #send result back  \r\n    Write-Information -Tags \"Audit\" -MessageData $log\r\n    throw \"Error connecting to Exchange Online. Error Message: $auditErrorMessage\"\r\n}\r\n\r\ntry {\r\n    try {\r\n        Write-Verbose \"Querying Exchange Online group with ID '$groupId'\"\r\n        $exchangeOnlineGroup = Get-Group -Identity $groupId -ErrorAction Stop\r\n        Write-Information \"Succesfully queried Exchange Online group with ID '$groupId'\"\r\n    }\r\n    catch {\r\n        $ex = $PSItem\r\n        if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {\r\n            $errorObject = Resolve-HTTPError -Error $ex\r\n    \r\n            $verboseErrorMessage = $errorObject.ErrorMessage\r\n    \r\n            $auditErrorMessage = $errorObject.ErrorMessage\r\n        }\r\n    \r\n        # If error message empty, fall back on $ex.Exception.Message\r\n        if ([String]::IsNullOrEmpty($verboseErrorMessage)) {\r\n            $verboseErrorMessage = $ex.Exception.Message\r\n        }\r\n        if ([String]::IsNullOrEmpty($auditErrorMessage)) {\r\n            $auditErrorMessage = $ex.Exception.Message\r\n        }\r\n    \r\n        Write-Verbose \"Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)\"\r\n        $Log = @{\r\n            Action            = \"Undefined\" # optional. ENUM (undefined = default) \r\n            System            = \"Exchange Online\" # optional (free format text) \r\n            Message           = \"Could not query Exchange Online group with ID '$groupId'. Error: $auditErrorMessage\" # required (free format text) \r\n            IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n            TargetDisplayName = \"Exchange Online\" # optional (free format text) \r\n            \r\n        }\r\n        #send result back  \r\n        Write-Information -Tags \"Audit\" -MessageData $log\r\n        throw \"Could not query Exchange Online group with ID '$groupId'. Error: $auditErrorMessage\"\r\n\r\n        # Clean up error variables\r\n        Remove-Variable 'verboseErrorMessage' -ErrorAction SilentlyContinue\r\n        Remove-Variable 'auditErrorMessage' -ErrorAction SilentlyContinue\r\n    }\r\n\r\n    # Add members\r\n    if ($usersToAdd -ne $null) {\r\n        try {\r\n            Write-Verbose \"Adding Exchange Online users [$($usersToAdd.Name -join ',')] to Exchange Online group [$($exchangeOnlineGroup.displayName)]\"\r\n            \r\n            foreach ($user in $usersToAdd) {\r\n                $addMemberParams = @{\r\n                    Identity                        = $exchangeOnlineGroup.Identity\r\n                    Member                          = $user.Id\r\n                    BypassSecurityGroupManagerCheck = $true\r\n                    Confirm                         = $false\r\n                    ErrorAction                     = 'Stop'\r\n                }\r\n\r\n                $addMember = Add-DistributionGroupMember @addMemberParams\r\n            }\r\n\r\n            Write-Information \"Succesfully added Exchange Online users [$($usersToAdd.Name -join ',')] to Exchange Online group [$($exchangeOnlineGroup.displayName)]\"\r\n            $Log = @{\r\n                Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                System            = \"Exchange Online\" # optional (free format text) \r\n                Message           = \"Succesfully added Exchange Online users [$($usersToAdd.Name -join ',')] to Exchange Online group [$($exchangeOnlineGroup.displayName)]\" # required (free format text) \r\n                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                TargetDisplayName = \"$($exchangeOnlineGroup.displayName)\" # optional (free format text) \r\n                TargetIdentifier  = \"$($exchangeOnlineGroup.Identity)\" # optional (free format text) \r\n            }\r\n            #send result back  \r\n            Write-Information -Tags \"Audit\" -MessageData $log\r\n        }\r\n        catch {\r\n            $ex = $PSItem\r\n            if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {\r\n                $errorObject = Resolve-HTTPError -Error $ex\r\n        \r\n                $verboseErrorMessage = $errorObject.ErrorMessage\r\n        \r\n                $auditErrorMessage = $errorObject.ErrorMessage\r\n            }\r\n        \r\n            # If error message empty, fall back on $ex.Exception.Message\r\n            if ([String]::IsNullOrEmpty($verboseErrorMessage)) {\r\n                $verboseErrorMessage = $ex.Exception.Message\r\n            }\r\n            if ([String]::IsNullOrEmpty($auditErrorMessage)) {\r\n                $auditErrorMessage = $ex.Exception.Message\r\n            }\r\n\r\n            Write-Verbose \"Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)\"\r\n            if ($auditErrorMessage -like \"*already a member of the group*\") {\r\n                Write-Information \"The recipient $($user.Name) is already a member of the group $($exchangeOnlineGroup.Identity)\";\r\n                $Log = @{\r\n                    Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                    System            = \"Exchange Online\" # optional (free format text) \r\n                    Message           = \"The recipient $($user.Name) is already a member of the group $($exchangeOnlineGroup.Identity)\" # required (free format text) \r\n                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = \"$($exchangeOnlineGroup.displayName)\" # optional (free format text) \r\n                    TargetIdentifier  = \"$($exchangeOnlineGroup.Identity)\" # optional (free format text) \r\n                }\r\n                #send result back  \r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n            }\r\n            elseif ($auditErrorMessage -like \"*object '$($exchangeOnlineGroup.id)' couldn't be found*\") {\r\n                Write-Warning \"Group $($exchangeOnlineGroup.Identity) couldn't be found. Possibly no longer exists. Skipping action\";\r\n                $Log = @{\r\n                    Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                    System            = \"Exchange Online\" # optional (free format text) \r\n                    Message           = \"Group $($exchangeOnlineGroup.Identity) couldn't be found. Possibly no longer exists. Skipping action\" # required (free format text) \r\n                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = \"$($exchangeOnlineGroup.displayName)\" # optional (free format text) \r\n                    TargetIdentifier  = \"$($exchangeOnlineGroup.Identity)\" # optional (free format text) \r\n                }\r\n                #send result back  \r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n            }\r\n            elseif ($auditErrorMessage -like \"*Couldn't find object \"\"$($user.Id)\"\"*\") {\r\n                Write-Warning \"User $($user.Name) couldn't be found. Possibly no longer exists. Skipping action\";\r\n                $Log = @{\r\n                    Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                    System            = \"Exchange Online\" # optional (free format text) \r\n                    Message           = \"User $($user.Name) couldn't be found. Possibly no longer exists. Skipping action\" # required (free format text) \r\n                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = \"$($exchangeOnlineGroup.displayName)\" # optional (free format text) \r\n                    TargetIdentifier  = \"$($exchangeOnlineGroup.Identity)\" # optional (free format text) \r\n                }\r\n                #send result back  \r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n            }\r\n            else {\r\n                Write-Error \"Could not add Exchange Online users [$($usersToAdd.Name -join ',')] to Exchange Online group [$($exchangeOnlineGroup.displayName). Error: $auditErrorMessage\"\r\n                $Log = @{\r\n                    Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                    System            = \"Exchange Online\" # optional (free format text) \r\n                    Message           = \"Could not add Exchange Online users [$($usersToAdd.Name -join ',')] to Exchange Online group [$($exchangeOnlineGroup.displayName). Error: $auditErrorMessage\" # required (free format text) \r\n                    IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = \"$($exchangeOnlineGroup.displayName)\" # optional (free format text) \r\n                    TargetIdentifier  = \"$($exchangeOnlineGroup.Identity)\" # optional (free format text) \r\n                }\r\n                #send result back  \r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n            }\r\n\r\n            # Clean up error variables\r\n            Remove-Variable 'verboseErrorMessage' -ErrorAction SilentlyContinue\r\n            Remove-Variable 'auditErrorMessage' -ErrorAction SilentlyContinue\r\n        }\r\n    }\r\n\r\n    # Remove members\r\n    if ($usersToRemove -ne $null) {\r\n        try {\r\n            Write-Verbose \"Removing Exchange Online users [$($usersToRemove.Name -join ',')] from Exchange Online group [$($exchangeOnlineGroup.displayName)]\"\r\n\r\n            foreach ($user in $usersToRemove) {\r\n                $removeMemberParams = @{\r\n                    Identity                        = $exchangeOnlineGroup.Identity\r\n                    Member                          = $user.Id\r\n                    BypassSecurityGroupManagerCheck = $true\r\n                    Confirm                         = $false\r\n                    ErrorAction                     = 'Stop'\r\n                }\r\n\r\n                $removeMember = Remove-DistributionGroupMember @removeMemberParams\r\n            }\r\n\r\n            Write-Information \"Succesfully removed Exchange Online users [$($usersToRemove.Name -join ',')] from Exchange Online group [$($exchangeOnlineGroup.displayName)]\"\r\n            $Log = @{\r\n                Action            = \"RevokeMembership\" # optional. ENUM (undefined = default) \r\n                System            = \"Exchange Online\" # optional (free format text) \r\n                Message           = \"Succesfully removed Exchange Online users [$($usersToRemove.Name -join ',')] from Exchange Online group [$($exchangeOnlineGroup.displayName)]\" # required (free format text) \r\n                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                TargetDisplayName = \"$($exchangeOnlineGroup.displayName)\" # optional (free format text) \r\n                TargetIdentifier  = \"$($exchangeOnlineGroup.Identity)\" # optional (free format text) \r\n            }\r\n            #send result back  \r\n            Write-Information -Tags \"Audit\" -MessageData $log\r\n        }\r\n        catch {\r\n            $ex = $PSItem\r\n            if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {\r\n                $errorObject = Resolve-HTTPError -Error $ex\r\n\r\n                $verboseErrorMessage = $errorObject.ErrorMessage\r\n\r\n                $auditErrorMessage = $errorObject.ErrorMessage\r\n            }\r\n        \r\n            # If error message empty, fall back on $ex.Exception.Message\r\n            if ([String]::IsNullOrEmpty($verboseErrorMessage)) {\r\n                $verboseErrorMessage = $ex.Exception.Message\r\n            }\r\n            if ([String]::IsNullOrEmpty($auditErrorMessage)) {\r\n                $auditErrorMessage = $ex.Exception.Message\r\n            }\r\n \r\n            Write-Verbose \"Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)\"\r\n            if ($auditErrorMessage -like \"*isn't a member of the group*\") {\r\n                Write-Information \"The recipient  $($user.Name) isn't a member of the group $($exchangeOnlineGroup.Identity))\";\r\n                $Log = @{\r\n                    Action            = \"RevokeMembership\" # optional. ENUM (undefined = default) \r\n                    System            = \"Exchange Online\" # optional (free format text) \r\n                    Message           = \"The recipient  $($user.Name) isn't a member of the group $($exchangeOnlineGroup.Identity))\" # required (free format text) \r\n                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = \"$($exchangeOnlineGroup.displayName)\" # optional (free format text) \r\n                    TargetIdentifier  = \"$($exchangeOnlineGroup.Identity)\" # optional (free format text) \r\n                }\r\n                #send result back  \r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n            }\r\n            elseif ($auditErrorMessage -like \"*object '$($exchangeOnlineGroup.id)' couldn't be found*\") {\r\n                Write-Warning \"Group $($exchangeOnlineGroup.Identity) couldn't be found. Possibly no longer exists. Skipping action\";\r\n                $Log = @{\r\n                    Action            = \"RevokeMembership\" # optional. ENUM (undefined = default) \r\n                    System            = \"Exchange Online\" # optional (free format text) \r\n                    Message           = \"Group $($exchangeOnlineGroup.Identity) couldn't be found. Possibly no longer exists. Skipping action\" # required (free format text) \r\n                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = \"$($exchangeOnlineGroup.displayName)\" # optional (free format text) \r\n                    TargetIdentifier  = \"$($exchangeOnlineGroup.Identity)\" # optional (free format text) \r\n                }\r\n                #send result back  \r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n            }\r\n            elseif ($auditErrorMessage -like \"*Couldn't find object \"\"$($user.Id)\"\"*\") {\r\n                Write-Warning \"User $($user.Name) couldn't be found. Possibly no longer exists. Skipping action\";\r\n                $Log = @{\r\n                    Action            = \"RevokeMembership\" # optional. ENUM (undefined = default) \r\n                    System            = \"Exchange Online\" # optional (free format text) \r\n                    Message           = \"User $($user.Name) couldn't be found. Possibly no longer exists. Skipping action\" # required (free format text) \r\n                    IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = \"$($exchangeOnlineGroup.displayName)\" # optional (free format text) \r\n                    TargetIdentifier  = \"$($exchangeOnlineGroup.Identity)\" # optional (free format text) \r\n                }\r\n                #send result back  \r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n            }\r\n            else {\r\n                Write-Error \"Could not remove Exchange Online users [$($usersToRemove.Name -join ',')] from Exchange Online group [$($exchangeOnlineGroup.displayName)]. Error: $auditErrorMessage\"\r\n                $Log = @{\r\n                    Action            = \"RevokeMembership\" # optional. ENUM (undefined = default) \r\n                    System            = \"Exchange Online\" # optional (free format text) \r\n                    Message           = \"Could not remove Exchange Online users [$($usersToRemove.Name -join ',')] from Exchange Online group [$($exchangeOnlineGroup.displayName)]. Error: $auditErrorMessage\" # required (free format text) \r\n                    IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                    TargetDisplayName = \"$($exchangeOnlineGroup.displayName)\" # optional (free format text) \r\n                    TargetIdentifier  = \"$($exchangeOnlineGroup.Identity)\" # optional (free format text) \r\n                }\r\n                #send result back  \r\n                Write-Information -Tags \"Audit\" -MessageData $log\r\n            }\r\n\r\n            # Clean up error variables\r\n            Remove-Variable 'verboseErrorMessage' -ErrorAction SilentlyContinue\r\n            Remove-Variable 'auditErrorMessage' -ErrorAction SilentlyContinue\r\n        }\r\n    }\r\n\r\n    # Update owners\r\n    if ($Owners -ne $null) {\r\n        try {\r\n            Write-Verbose \"Updating owners to [$($Owners.Name -join ',')] for Exchange Online group [$($exchangeOnlineGroup.displayName)]\"\r\n\r\n            $updateOwnersParams = @{\r\n                Identity                        = $exchangeOnlineGroup.Identity\r\n                ManagedBy                       = $Owners.userPrincipalName\r\n                BypassSecurityGroupManagerCheck = $true\r\n                Confirm                         = $false\r\n                ErrorAction                     = 'Stop'\r\n            }\r\n\r\n            $updateOwners = Set-DistributionGroup @updateOwnersParams\r\n\r\n            Write-Information \"Succesfully updated owners to [$($Owners.Name -join ',')] for Exchange Online group [$($exchangeOnlineGroup.displayName)]\"\r\n            $Log = @{\r\n                Action            = \"UpdateResource\" # optional. ENUM (undefined = default) \r\n                System            = \"Exchange Online\" # optional (free format text) \r\n                Message           = \"Succesfully updated owners to [$($Owners.Name -join ',')] for Exchange Online group [$($exchangeOnlineGroup.displayName)]\" # required (free format text) \r\n                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                TargetDisplayName = \"$($exchangeOnlineGroup.displayName)\" # optional (free format text) \r\n                TargetIdentifier  = \"$($exchangeOnlineGroup.Identity)\" # optional (free format text) \r\n            }\r\n            #send result back  \r\n            Write-Information -Tags \"Audit\" -MessageData $log\r\n        }\r\n        catch {\r\n            $ex = $PSItem\r\n            if ( $($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {\r\n                $errorObject = Resolve-HTTPError -Error $ex\r\n        \r\n                $verboseErrorMessage = $errorObject.ErrorMessage\r\n        \r\n                $auditErrorMessage = $errorObject.ErrorMessage\r\n            }\r\n        \r\n            # If error message empty, fall back on $ex.Exception.Message\r\n            if ([String]::IsNullOrEmpty($verboseErrorMessage)) {\r\n                $verboseErrorMessage = $ex.Exception.Message\r\n            }\r\n            if ([String]::IsNullOrEmpty($auditErrorMessage)) {\r\n                $auditErrorMessage = $ex.Exception.Message\r\n            }\r\n\r\n            Write-Verbose \"Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($verboseErrorMessage)\"\r\n            Write-Error \"Could not update owners $($Owners.Name -join ',')] for Exchange Online group [$($exchangeOnlineGroup.displayName)]. Error: $auditErrorMessage\"\r\n            $Log = @{\r\n                Action            = \"UpdateResource\" # optional. ENUM (undefined = default) \r\n                System            = \"Exchange Online\" # optional (free format text) \r\n                Message           = \"Could not update owners $($Owners.Name -join ',')] for Exchange Online group [$($exchangeOnlineGroup.displayName)]. Error: $auditErrorMessage\" # required (free format text) \r\n                IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                TargetDisplayName = \"$($exchangeOnlineGroup.displayName)\" # optional (free format text) \r\n                TargetIdentifier  = \"$($exchangeOnlineGroup.Identity)\" # optional (free format text) \r\n            }\r\n            #send result back  \r\n            Write-Information -Tags \"Audit\" -MessageData $log\r\n            # Clean up error variables\r\n            Remove-Variable 'verboseErrorMessage' -ErrorAction SilentlyContinue\r\n            Remove-Variable 'auditErrorMessage' -ErrorAction SilentlyContinue\r\n        }\r\n    }    \r\n}\r\nfinally {\r\n    Write-Verbose \"Closing Exchange Online connection\"\r\n    $exchangeSessionEnd = Disconnect-ExchangeOnline -Confirm:$false -Verbose:$false -ErrorAction Stop      \r\n    Write-Information \"Successfully closed Exchange Online connection\"\r\n}","runInCloud":false}
'@ 

Invoke-HelloIDDelegatedForm -DelegatedFormName $delegatedFormName -DynamicFormGuid $dynamicFormGuid -AccessGroups $delegatedFormAccessGroupGuids -Categories $delegatedFormCategoryGuids -UseFaIcon "True" -FaIcon "fa fa-users" -task $tmpTask -returnObject ([Ref]$delegatedFormRef) 
<# End: Delegated Form #>

