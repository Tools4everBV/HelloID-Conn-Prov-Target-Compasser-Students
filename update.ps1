#####################################################
# HelloID-Conn-Prov-Target-Compasser-Students-Update
#
# Version: 1.1.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()
$LocationsContractFilter = { $_.Location.Code } # The field in the contracts where the (school)location can be found
$studentNumber = $p.ExternalId   # the field in the person where the studentnumber is found
$HelloIDGender = $p.Details.gender #the field in the person where the gender is found

$updatePersonOnCreate = $false   # true: perfom update if account already exist on new location, false: only enable account if already exist in new location

# mapping between location and project_id
$projectHashTable = @{
    "location1 - Compasser" = 1001
    "location2 - Compasser" = 1002
    "location3 - Compasser" = 1003
    "location4 - Compasser" = 1004
    "location5 - Compasser" = 1005
    "location6 - Compasser" = 1006
}
# Account mapping
$account = [PSCustomObject]@{
    remote_id           = $StudentNumber
    email               = "$($p.Accounts.MicrosoftActiveDirectory.mail)"
    project_id          = ""                                      #Project_id determined automatically later in script
    firstname           = $p.Name.GivenName
    gender              = "U"                                       #gender determined automatically later in script
    lastname            = $p.Name.FamilyName
    letters             = $p.Name.Initials
    linkname            = $p.Name.FamilyNamePrefix
    remindoconnect_code = $studentNumber
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions

function Convert-PortfolioToAccount {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject] $Account,

        [Parameter(Mandatory)]
        [PSCustomObject] $Portfolio

    )
    $curAccount = [PSCustomObject]@{}

    $null = $Account.PSObject.Properties.foreach{
        $curAccount | Add-Member -MemberType NoteProperty -Name $($_.Name) -Value  ($Portfolio.$($_.Name) -as $_.TypeNameOfValue)
    }
    write-output $curAccount
}

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

function Get-CurrentLocationsFromContracts {
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


#endregion

# Begin
try {
    #complete the $acount object with calculated

    # Add gender to account
    [string] $Genderstring = ConvertTo-Gender($HelloIDGender)
    $account.gender = $Genderstring
    # Read the school locations where the account is to be created from the contracts
    # only one active location is allowed
    $contractsInScope = $p.contracts | Where-Object { $_.Context.InConditions -eq $true }
    if ($null -eq $contractsInScope) {
        throw "Unable to create account for student [$studentNumber]. No contracts in scope"
    }
    $locationList = Get-CurrentLocationsFromContracts ($contractsInScope) -LocationsContractFilter $LocationsContractFilter

    # Check that there is  exact 1 location for the user, calculate the project_id for the location
    # and set the project_id for the account.

    if ($locationList.count -ne 1) {
        if ($locationList.count -eq 0 ) {
            throw "Unable to update account for student [$studentNumber]. No location found for contracts in scope"
        }
        else {
            throw "Unable to update account for student [$studentNumber]. Multiple locations [$($locationList -join ', ' )] found for contracts in scope"
        }
    }
    $location = $locationList[0]
    $project_id = $projectHashTable[$location]
    if ($null -eq $project_id) {
        throw "Unable to update account for student [$studentNumber]. No Mapping to [project_id] specified for location [$location]"
    }
    $account.project_id = $project_id

    Write-Verbose "Verifying if a Compasser-Students account for [$($p.DisplayName)] exists"

    # Verify if the account must be updated

    $accessToken = Get-AccessToken

    $splatParams = @{
        Uri         = "$($config.BaseUrl)/oauth2/v1/resource/portfolios/$aRef"
        AccessToken = $accessToken
    }
    $portFolioResult = Invoke-CompasserRestMethod @splatParams
    $currentAccount = Convert-PortfolioToAccount -Account $account -Portfolio $portfolioResult.portfolios

    # Always compare the account against the current account in target system
    $splatCompareProperties = @{
        ReferenceObject  = @($currentAccount.PSObject.Properties)
        DifferenceObject = @($account.PSObject.Properties)
    }
    $propertiesChanged = (Compare-Object @splatCompareProperties -PassThru).Where({ $_.SideIndicator -eq '=>' })
    Write-Verbose "The Properties that are changed are [$propertiesChanged]"
    if (($null -ne $propertiesChanged) -and ($propertiesChanged.count -ne 0)) {

        if ($propertiesChanged.Name -contains "remote_id") {
            throw("Unable to update account for student [$studentNumber]. remote_id is requested to be changed from [$($currentAccount.remote_id)] to [$($account.remote_id)], which is not allowed")

        }
        elseif ($propertiesChanged.Name -contains "project_id") {
            $Action = 'CreateArchive'
            $dryRunMessage = "Account project id changed. Archiving old account and creating new account)]"
        }
        else {
            $action = 'Update'
            $dryRunMessage = "Account property(s) required to update: [$($propertiesChanged.name -join ",")]"
        }

    }
    else {
        $action = 'NoChanges'
        $dryRunMessage = 'No changes will be made to the account during enforcement'
    }

    Write-Verbose $dryRunMessage


    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $dryRunMessage"
    }

    # Process

    if (-not($dryRun -eq $true)) {
        switch ($action) {

            'CreateArchive' {
                # Archive the current account

                $auditMessage = "project_id changed from [$($currentAccount.project_id)] to [$($Account.project_id)]. Archive current account with portfolioId [$aref] and create-correlate new account)"
                $auditLogs.Add([PSCustomObject]@{
                        Message = $auditMessage
                        IsError = $false
                    })
                $body = @{
                    status     = "inactive"
                    project_id = $currentAccount.project_id
                }
                $splatParams = @{
                    Uri         = "$($config.BaseUrl)/oauth2/v1/resource/portfolios/$aRef"
                    AccessToken = $accessToken
                    Method      = "PUT"
                    body        = $body | ConvertTo-Json
                }
                $null = Invoke-CompasserRestMethod @splatparams

                #create new account
                # correlate existing account in new location
                # Correlate the account by remote_id and project_id

                $splatParams = @{
                    Uri         = "$($config.BaseUrl)/oauth2/v1/resource/portfolios?filter[project_id]=$($account.project_id)&filter[remote_id]=$($account.remote_id)"
                    AccessToken = $accessToken
                }
                $portfolioResult = Invoke-CompasserRestMethod @splatParams
                $responseUser = $null

                if (($null -ne $portfolioResult.portfolios) -and ($portfolioResult.portfolios.length -gt 1)) {
                    throw "Unable to create account for student [$studentNumber]. Multiple accounts returned by [($splatParams.Uri)]"
                }

                if (($null -ne $portfolioResult.portfolios)) {
                    $responseUser = $portfolioResult.portfolios[0]
                }

                if ($null -eq $responseUser) {
                    $CreateDetailaction = 'Create-Correlate'
                }
                elseif ($updatePersonOnCreate -eq $true) {
                    $CreateDetailaction = 'Update-Correlate'
                }
                else {
                    $CreateDetailaction = 'activate-Correlate'
                }

                switch ($CreateDetailaction) {
                    'Create-Correlate' {
                        $body = @{
                            email               = $account.email
                            firstname           = $account.firstname
                            gender              = $account.gender
                            lastname            = $account.lastname
                            letters             = $account.letters
                            remote_id           = $account.remote_id
                            linkname            = $account.linkname
                            remindoconnect_code = $account.remindoconnect_code 
                            project_id          = $account.project_id
                            status              = "active"
                        }
                        $splatParams = @{
                            Uri         = "$($config.BaseUrl)/oauth2/v1/resource/portfolios"
                            AccessToken = $accessToken
                            Method      = "POST"
                            body        = $body
                        }
                        $createResult = Invoke-CompasserRestMethod @splatparams

                        #get result of new account
                        $splatParams = @{
                            Uri         = "$($createResult.location)"
                            AccessToken = $accessToken
                        }
                        $queryResult = invoke-CompasserRestMethod @splatParams
                        $responseUser = $queryResult.portfolios[0]

                        $aRef = $responseUser.id
                        $auditLogs.Add([PSCustomObject]@{
                                Message = "create account with new aref [$aRef]  was successful"
                                IsError = $false
                            })
                        break
                    }
                    'update-Correlate' {
                        $aRef = $responseUser.id
                        Write-Verbose "Updating Compasser account with accountReference: [$aRef]"
                        $body = @{
                            email               = $account.email
                            firstname           = $account.firstname
                            gender              = $account.gender
                            lastname            = $account.lastname
                            letters             = $account.letters
                            linkname            = $account.linkname
                            remindoconnect_code = $account.remindoconnect_code 
                            project_id          = $account.project_id
                            status              = "active"
                        }
                        $splatParams = @{
                            Uri         = "$($config.BaseUrl)/oauth2/v1/resource/portfolios/$aRef"
                            AccessToken = $accessToken
                            Method      = "PUT"
                            body        = $body | ConvertTo-Json
                        }
                        $null = Invoke-CompasserRestMethod @splatparams
                        $success = $true
                        $auditLogs.Add([PSCustomObject]@{
                                Message = "Update account with new aref [$aRef]  was successful"
                                IsError = $false
                            })
                        break

                    }
                    'activate-Correlate' {
                        $aRef = $responseUser.id
                        Write-Verbose "Updating Compasser account with accountReference: [$aRef]"
                        $body = @{
                            status     = "active"
                            project_id = $account.project_id
                        }
                        $splatParams = @{
                            Uri         = "$($config.BaseUrl)/oauth2/v1/resource/portfolios/$aRef"
                            AccessToken = $accessToken
                            Method      = "PUT"
                            body        = $body | ConvertTo-Json
                        }
                        $null = Invoke-CompasserRestMethod @splatparams
                        $success = $true
                        $auditLogs.Add([PSCustomObject]@{
                                Message = "activate account with new aref [$aRef] was successful"
                                IsError = $false
                            })
                        break
                    }
                }
                break
            }
            'Update' {
                Write-Verbose "Updating Compasser account with accountReference: [$aRef]"
                $body = @{
                    email               = $account.email
                    firstname           = $account.firstname
                    gender              = $account.gender
                    lastname            = $account.lastname
                    letters             = $account.letters
                    linkname            = $account.linkname
                    remindoconnect_code = $account.remindoconnect_code 
                    project_id          = $account.project_id
                }
                $splatParams = @{
                    Uri         = "$($config.BaseUrl)/oauth2/v1/resource/portfolios/$aRef"
                    AccessToken = $accessToken
                    Method      = "PUT"
                    body        = $body | ConvertTo-Json
                }
                $null = Invoke-CompasserRestMethod @splatparams
                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                        Message = 'Update account was successful'
                        IsError = $false
                    })
                break
            }

            'NoChanges' {
                Write-Verbose "No changes to Compasser account with accountReference: [$aRef]"

                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                        Message = 'No changes where required for the account'
                        IsError = $false
                    })
                break
            }
        }
    }
}
catch {
    $success = $false
    $ex = $PSItem

    $errorObj = Resolve-CompasserError -ExceptionObject $ex
    $auditMessage = "Could not update Compasser account with id [$aref]. Error: $($errorObj.FriendlyMessage)"
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
        Account          = $account
        Auditlogs        = $auditLogs
        AccountReference = $aRef
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}