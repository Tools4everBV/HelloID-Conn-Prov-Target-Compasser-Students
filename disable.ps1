##################################################
# HelloID-Conn-Prov-Target-Compasser-Students-Disable
# PowerShell V2
##################################################

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

#endregion

try {
    # Verify if [accountReference] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-Information 'Verifying if a Compasser-Students account exists'   
    
    $accessToken = Get-AccessToken
    $splatParams = @{
        Uri         = "$($ActionContext.Configuration.BaseUrl)/oauth2/v1/resource/portfolios/$($actionContext.References.Account)"
        AccessToken = $accessToken
    }
    $portFolioResult = Invoke-CompasserRestMethod @splatParams
    $correlatedPortfolio = $portfolioResult.portfolios    
    if ($null -ne $correlatedPortfolio) {
        $lifecycleProcess = 'DisableAccount'
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    # Process
    switch ($lifecycleProcess) {
        'DisableAccount' {


            $splatParams = @{
                Uri         = "$($ActionContext.Configuration.BaseUrl)/oauth2/v1/resource/portfolios/$($actionContext.References.Account)"
                AccessToken = $accessToken
                Method      = "PUT"
                Body        = @{
                    status     = 'inactive'
                    project_id = $correlatedPortfolio.project_id
                } | ConvertTo-Json
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Disabling Compasser-Students account with accountReference: [$($actionContext.References.Account)]"
                $null = Invoke-CompasserRestMethod @splatparams                   
            }
            else {
                Write-Information "[DryRun] Disable Compasser-Students account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            # Make sure to filter out arrays from $outputContext.Data (If this is not mapped to type Array in the fieldMapping). This is not supported by HelloID.
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Disable account: [$($actionContext.References.Account)] was successful. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Compasser-Students account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Compasser-Students account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
                })
            break
        }
    }
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CompasserError -ExceptionObject $ex
        $auditLogMessage = "Could not disable Compasser-Students account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage). Action initiated by: [$($actionContext.Origin)]"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not disable Compasser-Students account: [$($actionContext.References.Account)]. Error: $($_.Exception.Message). Action initiated by: [$($actionContext.Origin)]"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}