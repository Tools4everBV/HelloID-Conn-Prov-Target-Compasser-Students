#################################################
# HelloID-Conn-Prov-Target-{connectorName}-Import
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

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

function ConvertTo-HelloIDImportAccountObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $AccountObject
    )
    process {
        # Making sure only fieldMapping fields are imported
        $helloidImportAccountObject = [PSCustomObject]@{} 
        foreach ($field in $actionContext.ImportFields) {            
            switch ($field) {
                default {                   
                    $helloidImportAccountObject | Add-Member -MemberType NoteProperty -Name $field -Value $AccountObject.$($field)
                }
            }
        }
        Write-Output $helloidImportAccountObject  
    }        
}
  
#endregion

try {
    Write-Information 'Starting Compasser-Students account entitlement import'
   
    $accessToken = Get-AccessToken
    # Example to replace the placeholder code with:
    $pageSize = 50
    $pageNumber = 1
    do {
        $splatImportAccountParams = @{
           Uri     = "$($ActionContext.Configuration.BaseUrl)/oauth2/v1/resource/portfolios?page=$($pageNumber)&page_size=$($pageSize)"
           AccessToken = $accessToken
        }
        $portfolioResult = Invoke-CompasserRestMethod @splatImportAccountParams
        $FoundAccounts = $portfolioResult.portfolios
        if ($null -ne $FoundAccounts) {
            foreach ($importedAccount in $FoundAccounts) {
                $data = ConvertTo-HelloIDImportAccountObject($importedAccount) 

                # Make sure the displayName has a value
                $displayName = "$($importedAccount.firstName) $($importedAccount.linkName) $($importedAccount.lastName)".trim()
                if ([string]::IsNullOrEmpty($displayName)) {
                    $displayName = $importedAccount.Id
                }

                # Make sure the userName has a value
                $username = "$($importedAccount.email)"
                if ([string]::IsNullOrWhiteSpace($username)) {
                    $username = "$($importedAccount.Id)"
                }

                # Set Enabled based on importedAccount status
                $isEnabled = $false
                if ($importedAccount.Status -eq 'Active') {
                    $isEnabled = $true
                }

                Write-Output @{
                    AccountReference = $importedAccount.Id
                    DisplayName      = $displayName
                    UserName         = $username
                    Enabled          = $isEnabled
                    Data             = $data
                }
            }
        }
        $pageNumber++
    } while ($pageNumber -le $portfolioResult.total_pages)   
   
    Write-Information 'Compasser-Students account entitlement import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CompasserError -ExceptionObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Compasser-Students account entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Compasser-Students account entitlements. Error: $($ex.Exception.Message)"
    }
}
