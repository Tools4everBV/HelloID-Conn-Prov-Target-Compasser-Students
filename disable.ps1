#####################################################
# HelloID-Conn-Prov-Target-Compasser-Students-Disable
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
function Get-AccessToken {
    Write-Verbose 'Retrieve OAuth token'
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
    Write-Output  $responseToken.access_token

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
    } else {
        $httpErrorObj.ErrorDetails = $ExceptionObject.ErrorDetails.Message
    }

    if ($null -ne $httpErrorObj.ErrorDetails) {
        try {
            $convertedErrorDetails = $httpErrorObj.ErrorDetails | ConvertFrom-Json
            $FriendlyMessage = $convertedErrorDetails.error_description
        } catch {
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
    Write-Verbose "Verifying if a Compasser-Students account for [$($p.DisplayName)] exists"
    if ($null -eq $aRef) {
        throw 'No account reference is available'
    }
    if (-not ($aRef -match '^[0-9]')) {
        throw 'The Account reference does not start with a numeric character, which is not allowed'
    }

    $accessToken = Get-AccessToken
    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add('Authorization', "Bearer $AccessToken")


    $splatParams = @{
        Uri     = "$($config.BaseUrl)/v1/resource/portfolios/$aref"
        Method  = 'Get'
        Headers = $headers
    }
    try {
        $responseUser = Invoke-RestMethod @splatParams  -Verbose:$false
        $action = 'Found'
        $dryRunMessage = "Disable Compasser-Students account for: [$($p.DisplayName)] will be executed during enforcement"
    } catch {
        $errorObj = Resolve-CompasserError -ExceptionObject $_
        if ($errorObj.FriendlyMessage -match 'not found') {
            $action = 'NotFound'
            $dryRunMessage = "Compasser-Students account for: [$($p.DisplayName)] not found. Possibly already deleted. Skipping action"
        } else {
            throw $_
        }
    }
    Write-Verbose $dryRunMessage



    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Found' {
                Write-Verbose "Disable Compasser-Students account with accountReference: [$aRef]"

                $splatParams = @{
                    Uri         = "$($config.BaseUrl)/v1/resource/portfolios/$aref"
                    Method      = 'PUT'
                    Headers     = $headers
                    ContentType = 'application/json'
                    Body        = @{
                        status     = 'inactive'
                        project_id = $responseUser.portfolios.project_id
                    } | ConvertTo-Json
                }
                $null = Invoke-RestMethod @splatParams  -Verbose:$false


                $auditLogs.Add([PSCustomObject]@{
                        Message = 'Disable account was successful'
                        IsError = $false
                    })
                break
            }

            'NotFound' {
                $auditLogs.Add([PSCustomObject]@{
                        Message = "Compasser-Students account for: [$($p.DisplayName)] not found. Possibily already deleted. Skipping action"
                        IsError = $false
                    })
                break
            }
        }

        $success = $true
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CompasserError -ExceptionObject $ex
        $auditMessage = "Could not disable Compasser-Students account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not disable Compasser-Students account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
    # End
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
