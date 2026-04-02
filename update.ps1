#################################################
# HelloID-Conn-Prov-Target-Compasser-Students-Update
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
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
function Get-CompasserAccount {
    [CmdletBinding()]
    param (        
    )
    $CorrelatedAccount = $null

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
            Uri         = "$($ActionContext.Configuration.BaseUrl)/oauth2/v1/resource/portfolios?filter[project_id]=$($ActionContext.Data.project_id)&filter[remote_id]=$($actionContext.Data.remote_id)"
            AccessToken = $accessToken
        }
        $portfolioResult = Invoke-CompasserRestMethod @splatParams
        $FoundAccounts = $portfolioResult.portfolios
        if (-not $null -eq $FoundAccounts) {
            if ($FoundAccounts.Count -eq 1) {
                $CorrelatedAccount = $FoundAccounts[0]
            }
            elseif ($FoundAccounts.Count -gt 1) {
                throw "Multiple accounts found for person where $correlationField is: [$correlationValue]"
            }       
   
        }
    }
    return $CorrelatedAccount
}

function ConvertTo-HelloIDAccountObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject] $Portfolio
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
    # Verify if [accountReference] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-Information 'Verifying if a Compasser-Students account exists'
    $correlatedAccount = 'userInfo'

    $accessToken = Get-AccessToken
    $splatParams = @{
        Uri         = "$($ActionContext.Configuration.BaseUrl)/oauth2/v1/resource/portfolios/$($actionContext.References.Account)"
        AccessToken = $accessToken
    }

    $portFolioResult = Invoke-CompasserRestMethod @splatParams
    $correlatedAccount = ConvertTo-HelloIDAccountObject -portfolio $portfolioResult.portfolios    
    
    # Make sure to filter out arrays from $outputContext.Data (If this is not mapped to type Array in the fieldmapping). This is not supported by HelloID.
    $outputContext.PreviousData = $correlatedAccount

    if ($null -ne $correlatedAccount) {

        $studentNumber = $correlatedAccount.remote_id 
        # Read the school locations where the account is to be created from the contracts
        # only one active location is allowed
        $contractsInScope = $personContext.Person.Contracts | Where-Object { $_.Context.InConditions -eq $true }
        if ($null -eq $contractsInScope) {
            throw "Unable to update account for student [$studentNumber)]. No contracts in scope"
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
   
        $ActionContext.Data | Add-Member -MemberType NoteProperty -Name 'project_id' -Value $project_id -Force


        # Always compare the account against the current account in target system
        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties)
            DifferenceObject = @($actionContext.Data.PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        if ($propertiesChanged) {

            if ($propertiesChanged.Name -contains "remote_id") {
                throw("Unable to update account for student [$studentNumber]. remote_id is requested to be changed from [$($correlatedAccount.remote_id)] to [$($actionContext.Data.remote_id)], which is not allowed")
            }

            if ($propertiesChanged.Name -contains "project_id") {
                $lifecycleProcess = 'CreateArchiveAccount'               
            }
            else {                
                $lifecycleProcess = 'UpdateAccount'              
            }
        }
        else {
            $lifecycleProcess = 'NoChanges'
        }
    }
    else {
        $lifecycleProcess = 'NotFound'
    }
    

    # Process
    switch ($lifecycleProcess) {
        'UpdateAccount' {
            Write-Information "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"

            $account = $correlatedAccount
            foreach ($property in $propertiesChanged) {
                $account | Add-Member -NotePropertyName $property.Name -NotePropertyValue $actionContext.Data.$($property.Name) -Force
            }
            $splatParams = @{
                Uri         = "$($ActionContext.Configuration.BaseUrl)/oauth2/v1/resource/portfolios/$($actionContext.References.Account)"
                AccessToken = $accessToken
                Method      = "PUT"
                body        = $account | ConvertTo-Json
            }
        
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating Compasser-Students account with accountReference: [$($actionContext.References.Account)]"
                $null = Invoke-CompasserRestMethod @splatparams
            }
            else {
                Write-Information "[DryRun] Update Compasser-Students account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            # Make sure to filter out arrays from $outputContext.Data (If this is not mapped to type Array in the fieldmapping). This is not supported by HelloID.
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                    IsError = $false
                })
            break
        }
        'CreateArchiveAccount' {

            # archive the old account
            $oldAccount = $correlatedAccount
            Write-Information "project_id changed from [$($oldAccount.project_id)] to[$($actionContext.Data.project_id)]. Archiving old account and creating/correlating new account. Old accountReference: [$($actionContext.References.Account)]"
            $auditMessage = "project_id changed from [$($oldAccount.project_id)] to [$($actionContext.Data.project_id)]. Archiving old account and creating/correlating new account. Old accountReference: [$($actionContext.References.Account)]"
            $outputContext.auditLogs.Add([PSCustomObject]@{
                    Message = $auditMessage
                    IsError = $false
                })
            $body = @{
                status     = "inactive"
                project_id = $oldAccount.project_id
            }
            $splatParams = @{
                Uri         = "$($ActionContext.Configuration.BaseUrl)/oauth2/v1/resource/portfolios/$($actionContext.References.Account)"
                AccessToken = $accessToken
                Method      = "PUT"
                body        = $body | ConvertTo-Json
            } 
            
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Archiving old Compasser-Students account with accountReference: [$($actionContext.References.Account)]"          
                $null = Invoke-CompasserRestMethod @splatparams
            }
            else {
                Write-Information "[DryRun] Archiving old Compasser-Students account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }          
        
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Archiving old account was successful"
                    IsError = $false
                })
        
            # correlate existing account in new location
            $CorrelatedNewAccount = Get-CompasserAccount
            if ($null -eq $CorrelatedNewAccount) {                             
                $ArchiveDetailaction = "Create"
            }
            else {
                $splatCompareProperties = @{
                    ReferenceObject  = @($CorrelatedNewAccount.PSObject.Properties)
                    DifferenceObject = @($actionContext.Data.PSObject.Properties)
                }
                $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
                if ($propertiesChanged) { 
                    $ArchiveDetailaction = 'Update-Correlate'              
                }                
                else {
                    $ArchiveDetailaction = 'activate-Correlate'
                }
            }
            switch ($ArchiveDetailaction) {
                'Create' {
                    $actionContext.Data | Add-Member -NotePropertyName "status" -NotePropertyValue "active" -Force
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
                        $outputContext.Data = ConvertTo-HelloIDAccountObject -portfolio $createdAccount
                        $outputContext.AccountReference = $createdAccount.Id                  
                    }
                    else {
                        Write-Information '[DryRun] Create and correlate Compasser-Students account, will be executed during enforcement'
                    }  

                    $auditLogMessage = "Create account was successful. New accountReference is: [$($outputContext.AccountReference)]"
                    $outputContext.Success = $true
                    $outputContext.AuditLogs.Add([PSCustomObject]@{                             
                            Message = $auditLogMessage
                            IsError = $false        
                        })
                    break
                    
                }
                'Update-Correlate' {
                    Write-Information "Correlating existing account. Account property(s) required to update: $($propertiesChanged.Name -join ', ')"

                    $account = $CorrelatedNewAccount
                    $account | Add-Member -NotePropertyName "status" -NotePropertyValue "active" -Force
                    $outputContext.AccountReference = $Account.Id          

                    foreach ($property in $propertiesChanged) {
                        $account | Add-Member -NotePropertyName $property.Name -NotePropertyValue $actionContext.Data.$($property.Name) -Force
                    }
                    $splatParams = @{
                        Uri         = "$($ActionContext.Configuration.BaseUrl)/oauth2/v1/resource/portfolios/$($outputContext.AccountReference)"
                        AccessToken = $accessToken
                        Method      = "PUT"
                        body        = $account | ConvertTo-Json
                    }
        
                    if (-not($actionContext.DryRun -eq $true)) {
                        Write-Information "Updating Compasser-Students account with accountReference: [$($outputContext.AccountReference)]"
                        $null = Invoke-CompasserRestMethod @splatparams
                    }
                    else {
                        Write-Information "[DryRun] Update Compasser-Students account with accountReference: [$($outputContext.AccountReference)], will be executed during enforcement"
                    }
                    $outputContext.Data = ConvertTo-HelloIDAccountObject -portfolio $Account                                 
                    $outputContext.Success = $true
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                            IsError = $false
                        })
                    break
                }
                'activate-Correlate' {
                    Write-Information 'Correlating and activating Compasser-Students account'
                    $account = $CorrelatedNewAccount
                    $account | Add-Member -NotePropertyName "status" -NotePropertyValue "active" -Force
                    $outputContext.AccountReference = $Account.Id           
                    
                    $splatParams = @{
                        Uri         = "$($ActionContext.Configuration.BaseUrl)/oauth2/v1/resource/portfolios/$($outputContext.AccountReference)"
                        AccessToken = $accessToken
                        Method      = "PUT"
                        body        = $account | ConvertTo-Json
                    }           
                    if (-not($actionContext.DryRun -eq $true)) {
                        Write-Information "activating Compasser-Students account with accountReference: [$($outputContext.AccountReference)]"
                        $null = Invoke-CompasserRestMethod @splatparams
                    }
                    else {
                        Write-Information "[DryRun] Update Compasser-Students account with accountReference: [$($outputContext.AccountReference)], will be executed during enforcement"
                    }
                    $outputContext.Data = ConvertTo-HelloIDAccountObject -portfolio $Account
                               
                    $outputContext.Success = $true
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                            IsError = $false
                        })
                    break                           
                }
            } 
            break
        }

        'NoChanges' {
            Write-Information "No changes to Compasser-Students account with accountReference: [$($actionContext.References.Account)]"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Skipped updating Compasser-Students account with AccountReference: [$($actionContext.References.Account)]. Reason: No changes."
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Compasser-Students account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Compasser-Students account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $true
                })
            break
        }
    }        
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CompasserError -ExceptionObject $ex
        $auditLogMessage = "Could not update Compasser-Students account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not update Compasser-Students account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}

