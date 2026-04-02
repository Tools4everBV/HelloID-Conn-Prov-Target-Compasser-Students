#################################################
# HelloID-Conn-Prov-Target-Compasser-Students-Create
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# mapping between location and project_id
$projectHashTable = @{
    "location1 - Compasser" = "1001"
    "location2 - Compasser" = "1002"
    "location3 - Compasser" = "1003"
    "location4 - Compasser" = "1004"
    "location5 - Compasser" = "1005"
    "location6 - Compasser" = "1006"
}
$LocationsContractFilter = { $_.Location.Code }

#region functions

function Resolve-CompasserError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ExceptionObject
    )

    $httpErrorObj = [PSCustomObject]@{
        ScriptLineNumber = $ExceptionObject.InvocationInfo.ScriptLineNumber
        Line             = $ExceptionObject.InvocationInfo.Line
        ErrorDetails     = $ExceptionObject.Exception.Message
        FriendlyMessage  = $ExceptionObject.Exception.Message
    }
    if (($null -eq $ExceptionObject.ErrorDetails) -or ([string]::IsNullOrWhiteSpace($ExceptionObject.ErrorDetails.Message))) {
        if ($null -ne $ExceptionObject.Exception.Response) {
            $responseStream = [System.IO.StreamReader]::new($ExceptionObject.Exception.Response.GetResponseStream())
            if ($null -ne $responseStream) {
                $httpErrorObj.ErrorDetails = $responseStream.ReadToEnd()
            }
        }
    }
    else {
        $httpErrorObj.ErrorDetails = $ExceptionObject.ErrorDetails.Message
    }

    if ($null -ne $httpErrorObj.ErrorDetails) {
        try {
            $convertedErrorDetails = $httpErrorObj.ErrorDetails | ConvertFrom-Json
            $FriendlyMessage = $convertedErrorDetails.error_description
        }
        catch {
            $FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        if ($null -ne $FriendlyMessage ) {
            $httpErrorObj.FriendlyMessage = $FriendlyMessage
        }
    }

    Write-Output $httpErrorObj

}


function Get-AccessToken {
    Write-Verbose "Retrieve OAuth token"
    $headers = @{
        'content-type' = 'application/json'
    }
    $body = @{  'grant_type' = 'client_credentials'
        'client_id'          = $($ActionContext.Configuration.ClientID)
        'client_secret'      = $($ActionContext.Configuration.ClientSecret)
    }
    $splatOauthParams = @{
        Uri     = "$($ActionContext.Configuration.BaseUrl)/oauth2/v1/token"
        Method  = 'POST'
        Headers = $Headers
        Body    = $body
    }

    if (-not  [string]::IsNullOrEmpty($ActionContext.Configuration.ProxyAddress)) {
        $splatOauthParams['Proxy'] = $ActionContext.Configuration.ProxyAddress
    }

    $responseToken = Invoke-RestMethod @splatOauthParams -Verbose:$false
    Write-output  $responseToken.access_token

}
function    Get-CurrentLocationsFromContracts {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Collections.Generic.List[Object]]
        $Contracts,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        $LocationsContractFilter
    )
    $Locations = [System.Collections.Generic.List[string]]::new()
    $result = $Contracts | Group-Object -Property $LocationsContractFilter
    foreach ($entry in $result) {
        $Locations.add($entry.Name)
    }
    return , $Locations
}
#en
function Invoke-CompasserRestMethod {
    [CmdletBinding()]
    param (
        [string]
        $Method = "GET",

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [object]
        $Body,

        [string]
        $ContentType = 'application/json',

        [System.Collections.IDictionary]
        $Headers = @{},

        [Parameter(Mandatory)]
        [string]
        $AccessToken
    )

    process {
        try {

            $headers.Add("Authorization", "Bearer $AccessToken")

            $splatParams = @{
                Uri         = $Uri
                Headers     = $Headers
                Method      = $Method
                ContentType = $ContentType
            }

            if (-not  [string]::IsNullOrEmpty($ActionContext.Configuration.ProxyAddress)) {
                $splatParams['Proxy'] = $ActionContext.Configuration.ProxyAddress
            }

            if ($Body) {               
                $splatParams['Body'] = $Body
            }
            Invoke-RestMethod @splatParams -Verbose:$false
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function ConvertTo-HelloIDAccountObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $Portfolio
    )
    process {
        # Making sure only fieldMapping fields are imported
        $helloidAccountObject = [PSCustomObject]@{} 
        $null = $outputContext.Data.PSObject.Properties.foreach{
            $helloidAccountObject | Add-Member -MemberType NoteProperty -Name $($_.Name) -Value  ($Portfolio.$($_.Name) -as $_.TypeNameOfValue)
        } 
        
        Write-Output $helloidAccountObject
    }
}

#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    $studentNumber = $Actioncontext.Data.remote_id 
    # Read the school locations where the account is to be created from the contracts
    # only one active location is allowed
    $contractsInScope = $personContext.Person.Contracts | Where-Object { $_.Context.InConditions -eq $true }
    if ($null -eq $contractsInScope) {
        throw "Unable to create account for student [$studentNumber)]. No contracts in scope"
    }
    $locationList = Get-CurrentLocationsFromContracts ($contractsInScope) -LocationsContractFilter $LocationsContractFilter

    # Check that there is  exact 1 location for the user, calculate the project_id for the location
    # and set the project_id for the account.

    if ($locationList.count -ne 1) {
        if ($locationList.count -eq 0 ) {
            throw "Unable to create account for student [$studentNumber]. No location found for contracts in scope"
        }
        else {
            throw "Unable to create account for student [$studentNumber]. Multiple locations [$($locationList -join ', ' )] found for contracts in scope"
        }
    }
    $location = $locationList[0]
    $project_id = $projectHashTable[$location]
    if ($null -eq $project_id) {
        throw "Unable to create account for student [$studentNumber)]. No Mapping to project_id specified for location [$location]"
    }
    $ActionContext.Data | Add-Member -MemberType NoteProperty -Name 'project_id' -Value $project_id -Force

    $accessToken = Get-AccessToken 

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Determine if a user needs to be [created] or [correlated]
        Write-Information "Verifying if a Compasser-Student account exists where $correlationField is: [$correlationValue] and project_id is: [$($ActionContext.Data.project_id)]"
           
        # Correlate the account by remote_id and project_id
        
        $splatParams = @{
            Uri         = "$($ActionContext.Configuration.BaseUrl)/oauth2/v1/resource/portfolios?filter[project_id]=$($ActionContext.Data.project_id)&filter[remote_id]=$($ActionContext.Data.remote_id)"
            AccessToken = $accessToken
        }
        $portfolioResult = Invoke-CompasserRestMethod @splatParams
        $FoundAccounts = $portfolioResult.portfolios
    
        if (($null -eq $FoundAccounts) -or $FoundAccounts.Count -eq 0) {
            $lifecycleProcess = 'CreateAccount'
        }
        elseif ($FoundAccounts.Count -eq 1) {
            $lifecycleProcess = 'CorrelateAccount'
            $CorrelatedAccount = $FoundAccounts[0]
        }
        else {
            throw "Multiple accounts found for person where $correlationField is: [$correlationValue]"
        }
    }
    else {
        $lifecycleProcess = 'CreateAccount'
    }

    # Process
    switch ($lifecycleProcess) {
        'CreateAccount' {
            $actionContext.Data | Add-Member -MemberType NoteProperty -Name 'status' -Value 'inactive' -Force
            $splatCreateParams = @{
                Uri         = "$($ActionContext.Configuration.BaseUrl)/oauth2/v1/resource/portfolios"
                AccessToken = $accessToken
                Method      = "POST"
                Body        = $actionContext.Data | ConvertTo-Json
            }
           
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating Compasser-Students account' 

                $createResult = Invoke-CompasserRestMethod @splatCreateParams

                $splatParams = @{
                    Uri         = "$($createResult.location)"
                    AccessToken = $accessToken
                }
                $queryResult = invoke-CompasserRestMethod @splatParams
                $createdAccount = $queryResult.portfolios[0]

                # Make sure to filter out arrays from $outputContext.Data (If this is not mapped to type Array in the fieldmapping). This is not supported by HelloID.
                $outputContext.Data = ConvertTo-HelloIDAccountObject -Portfolio $createdAccount
                $outputContext.AccountReference = $createdAccount.Id
            }
            else {
                Write-Information '[DryRun] Create and correlate Compasser-Students account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating Compasser-Students account'

            # Make sure to filter out arrays from $outputContext.Data (If this is not mapped to type Array in the fieldmapping). This is not supported by HelloID.
            $outputContext.Data = ConvertTo-HelloIDAccountObject -Portfolio $CorrelatedAccount
            $outputContext.AccountReference = $CorrelatedAccount.Id
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)] and project_id : [$($ActionContext.Data.project_id)]"
            break
        }
    }

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $lifecycleProcess
            Message = $auditLogMessage
            IsError = $false
        })
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CompasserError -ExceptionObject $ex
        $auditLogMessage = "Could not create or correlate Compasser-Students account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not create or correlate Compasser-Students account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}