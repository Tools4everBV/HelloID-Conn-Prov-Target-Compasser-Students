#####################################################
# HelloID-Conn-Prov-Target-Compasser-Students-Create
#
# Version: 1.0.0
#####################################################
#region Initalization functions

# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()
$LocationsContractFilter = { $_.Location.Code } # The field in the contracts where the (school)location can be found
$studentNumber = $p.ExternalId   # the field in the person where the studentnumber is found
$HelloIDGender = $p.Details.gender #the field in the person where the gender is found


# mapping between location and project_id
$projectHashTable = @{
    "location1 - Compasser"     = 1001
    "location2 - Compasser"     = 1002
    "location3 - Compasser"     = 1003
    "location4 - Compasser"     = 1004
    "location5 - Compasser"     = 1005
    "location6 - Compasser"     = 1006
}

# Account mapping
$account = [PSCustomObject]@{
    remote_id     = $StudentNumber
    email         = "$($p.Accounts.MicrosoftActiveDirectory.mail)"
    project_id    = ""                                       #Project_id determined automatically later in script
    firstname     = $p.Name.GivenName
    gender        = ""                                       #gender determined automatically later in script
    lastname      = $p.Name.FamilyName
    letters       = $p.Name.Initials
}


# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Set to true if accounts in the target system must be updated
$updatePerson = $false

#region functions

function ConvertTo-Gender {
    [CmdletBinding()]
    param (
        [string]
        $Source = "U"
    )
    switch ($Source.ToLower()) {
        { ($_ -eq "man") -or ($_ -eq "male") } {
            $gender = "M"
        }
        { ($_ -eq "vrouw") -or ($_ -eq "female") } {
            $gender = "F"
        }
        Default {
            $gender = "U"
        }
    }
    write-output $gender
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
#endregion

function Get-AccessToken {
    Write-Verbose "Retrieve OAuth token"
    $headers = @{
        'content-type' = 'application/json'
    }
    $body = @{  'grant_type' = 'client_credentials'
        'client_id'          = $($config.ClientID)
        'client_secret'      = $($config.ClientSecret)
    }
    $splatOauthParams = @{
        Uri     = "$($config.BaseUrl)/oauth2/v1/token"
        Method  = 'POST'
        Headers = $Headers
        Body    = $body
    }

    if (-not  [string]::IsNullOrEmpty($config.ProxyAddress)) {
        $splatOauthParams['Proxy'] = $config.ProxyAddress
    }

    $responseToken = Invoke-RestMethod @splatOauthParams -Verbose:$false
    Write-output  $responseToken.access_token

}

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

            if (-not  [string]::IsNullOrEmpty($config.ProxyAddress)) {
                $splatParams['Proxy'] = $config.ProxyAddress
            }

            if ($Body) {
                Write-Verbose 'Adding body to request'
                $splatParams['Body'] = $Body
            }
            Invoke-RestMethod @splatParams -Verbose:$false
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
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

    if ($null -ne $httpErrorObj.ErrorDetails)
    {
        try {
            $convertedErrorDetails = $httpErrorObj.ErrorDetails | ConvertFrom-Json
            $FriendlyMessage = $convertedErrorDetails.error_description
        } catch {
            $FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        if ($null -ne $FriendlyMessage )
        {
            $httpErrorObj.FriendlyMessage = $FriendlyMessage
        }
    }

    Write-Output $httpErrorObj

}

#endregion

# Begin
try {

    # Add gender to account
    $account.gender = ConvertTo-Gender($HelloIDGender)

    # Read the school locations where the account is to be created from the contracts
    # only one active location is allowed
    $contractsInScope = $p.contracts | Where-Object { $_.Context.InConditions -eq $true }
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
        throw "Unable to create account for student [$studentNumber)]. No Mapping to [project_id] specified for location [$location]"
    }

    $account.project_id = $project_id

    # Verify if a user must be either [created and correlated], [updated and correlated] or just [correlated]

    $accessToken = Get-AccessToken

    # Correlate the account by remote_id and project_id

    $splatParams = @{
        Uri         = "$($config.BaseUrl)/oauth2/v1/resource/portfolios?filter[project_id]=$($account.Project_id)&filter[remote_id]=$($account.remote_id)"
        AccessToken = $accessToken
    }
    $portfolioResult = Invoke-CompasserRestMethod @splatParams

    if (($null -ne $portfolioResult.portfolios) -and ($portfolioResult.portfolios.length -gt 1)) {
        throw "Unable to create account for student $studentNumber. Multiple accounts returned by [($splatParams.Uri)]"
    }

    if (($null -ne $portfolioResult.portfolios)) {
        $responseUser = $portfolioResult.portfolios[0]
    }

    if ($null -eq $responseUser) {
        $action = 'Create-Correlate'
    }
    elseif ($updatePerson -eq $true) {
        $action = 'Update-Correlate'
    }
    else {
        $action = 'Correlate'
    }

    # Add a warning message showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $action Compasser-Students account for: [$($p.DisplayName)], StudentNr : [$($account.remote_id), project_id : [$($account.project_id) will be executed during enforcement"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Create-Correlate' {
                Write-Verbose "Creating and correlating Compasser-Students account"
                $body = @{
                    email      = $account.email
                    firstname  = $account.firstname
                    gender     = $account.gender
                    lastname   = $account.lastname
                    letters    = $account.letters
                    remote_id  = $account.remote_id
                    project_id = $account.project_id
                    status = "inactive"
                }
                $splatParams = @{
                    Uri         = "$($config.BaseUrl)/oauth2/v1/resource/portfolios"
                    AccessToken = $accessToken
                    Method      = "POST"
                    body        = $body
                }
                $createResult = Invoke-CompasserRestMethod @splatparams

                $splatParams = @{
                    Uri         = "$($createResult.location)"
                    AccessToken = $accessToken
                }
                $queryResult = invoke-CompasserRestMethod @splatParams
                $responseUser = $queryResult.portfolios[0]
                break;
            }

            'Update-Correlate' {
                Write-Verbose "Updating and correlating Compasser-Students account"
                $body = @{
                    email      = $account.email
                    firstname  = $account.firstname
                    gender     = $account.gender
                    lastname   = $account.lastname
                    letters    = $account.letters
                    project_id = $account.project_id
                }
                $splatParams = @{
                    Uri         = "$($config.BaseUrl)/oauth2/v1/resource/portfolios/$($responseUser.id)"
                    AccessToken = $accessToken
                    Method      = "PUT"
                    body        = $body
                }
                $null = Invoke-CompasserRestMethod @splatparams

                break
            }

            'Correlate' {
                Write-Verbose "Correlating Compasser-Students account"
                break
            }
        }
        $accountRef = $responseUser.id

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = "$action account was successful. AccountReference is: [$accountRef]. StudentNr is : [$($account.remote_id). project_id is : [$($account.project_id)]"
                IsError = $false
            })
    }

}
catch {
    $success = $false
    $ex = $PSItem
    $errorObj = Resolve-CompasserError -ExceptionObject $ex
    $auditMessage = "Could not $action Compasser-Students account. Error: $($errorObj.FriendlyMessage)"
    Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"

    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
    # End
}
finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountRef
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
