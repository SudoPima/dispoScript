#############################################################################################################################
$global:event=$null

$logfile = "$PSScriptRoot\postScript_test2.log"

function Log($String) {
    "[$([DateTime]::Now)]: $string" | Out-File -FilePath $logfile -Append
}

#############################################################################################################################
function getGUID($hostName) {
    $getUri = 'https://api.amp.cisco.com/v1/computers?hostname%5B%5D=' + $hostName

    $edrComputer = Invoke-RestMethod -Method GET -Headers $Headers -Uri $getUri -ContentType "application/json" -UseBasicParsing  -ErrorVariable $RestError -ErrorAction SilentlyContinue
    if ($RestError) {
        $HttpStatusCode = $RestError.ErrorRecord.Exception.Response.StatusCode.value__
        $HttpStatusDescription = $RestError.ErrorRecord.Exception.Response.StatusDescription
        return "Http Status Code: $($HttpStatusCode) - Http Status Description: $($HttpStatusDescription)"
        Log "   - Http Status Code: $($HttpStatusCode) - Http Status Description: $($HttpStatusDescription)"
        Write-Host "Http Status Code: $($HttpStatusCode) - Http Status Description: $($HttpStatusDescription)" -ForegroundColor Red
    }
    
    if ($null -ne $edrComputer.data.connector_guid) {
        Log "   - GUID Found: $($guid) for: $($hostname)"
        Write-Host "GUID Found: $($guid) for: $($hostname)" -ForegroundColor Green
        return $guid
    }
    else {
        Log "   - Could not find GUID for: $($hostname)"
        Write-Host "Could not find GUID for: $($hostname)" -ForegroundColor DarkYellow
        return  "GUID NOT FOUND"
    }
}
#############################################################################################################################

function DeleteGUID($guids) {
    foreach ($guid in $guids) {
        if ($guid -ne "GUID NOT FOUND") {
            $delUri = 'https://api.amp.cisco.com/v1/computers/' + $guid
            $Response = Invoke-RestMethod -Method Delete -Headers $Headers -Uri $delUri -ContentType "application/json" -UseBasicParsing  -ErrorVariable $RestError -ErrorAction SilentlyContinue 
        
            if ($RestError){
                $HttpStatusCode = $RestError.ErrorRecord.Exception.Response.StatusCode.value__
                $HttpStatusDescription = $RestError.ErrorRecord.Exception.Response.StatusDescription
                return "Http Status Code: $($HttpStatusCode) - Http Status Description: $($HttpStatusDescription)"
                Log "   - Http Status Code: $($HttpStatusCode) - Http Status Description: $($HttpStatusDescription)"
                Write-Host "Http Status Code: $($HttpStatusCode) - Http Status Description: $($HttpStatusDescription)" -ForegroundColor Red
            }
            Else {
                return "$($response.data.deleted): $($date)"
                Log "   - Successfully deleted: $($guid)"
                Write-Host "Successfully deleted: $($guid)" -ForegroundColor Green
            }
        }
        else {
            return "Checked: $($date)"
            Log "   - Guid not found: $($guid)"
            Write-Host "Guid not found: $($guid)" -ForegroundColor DarkYellow
        }
    }
}
#############################################################################################################################

function deleteSCCM($hostName) {
    try {
        Remove-CMDevice -DeviceName $hostname -Force -ErrorAction SilentlyContinue 
        return $($date)
        Log "   - Successfully deleted: $($hostName) from SCCM"
        Write-Host "Successfully deleted: $($hostName) from SCCM" -ForegroundColor Green
    }
    catch {
        return "Failed to Remove: $($hostName) from SCCM"
        Log "   - Unkown Error - Could not delete: $($hostName) from SCCM"
        Write-Host "Unkown Error - Could not delete: $($hostName) from SCCM" -ForegroundColor Red
    }
}
#############################################################################################################################
$credential = Get-Credential

$client_id = Read-Host 'Enter the Client ID: '
$api_key = Read-host 'Enter the API Key: '

$EncodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($('{0}:{1}' -f $client_id, $api_key)))
$Headers = @{'Authorization' = "Basic $($EncodedCreds)"; 'accept' = 'application/json'; 'Content-type' = 'application/json'; 'Accept-Encoding' = 'gzip, deflate'} 

$adInventory = Import-csv .\ADInventory.csv
$disposedComputers = Import-csv .\pcc-nums.csv

$date = Get-Date -Format "yyyy-MM-dd"

# Site configuration
$SiteCode = "PCC" # Site code 
$ProviderMachineName = "do-sccm.pcc-domain.pima.edu" # SMS Provider machine name

# Customizations
$initParams = @{}

# Import the ConfigurationManager.psd1 module 
if ($null -eq (Get-Module ConfigurationManager)) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if ($null -eq (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams -Credential $credential
}
#############################################################################################################################
foreach ($computer in (($disposedComputers).'PCC#' | Where-Object {$_ -match "\d{6}"})) {
    Log "   - Looking for Hostname for PCC#: $($computer)"
    Write-Host "Looking for Hostname for PCC#: $($computer)" -ForegroundColor Cyan
    $computerLog = [PSCustomObject]@{
        PCC_Number        = $computer
        HostName          = $null
        EDRGuid           = $null
        ADRemoved         = $null
        SCCMRemoved       = $null
        EDRRemoved        = $null
    }
    # Set the current location to be the site code.
    Set-Location "$($SiteCode):\" @initParams
    
    $invObj = $adInventory | Where-Object {$_.'Name' -match "$($computer)[a-z]{2}$"}
    $adObj = (Get-ADComputer -Filter "Name -Like '*$($computer)*'" | Where-Object {$_.Name -match "$($computer)[a-z]{2}$"}).Name
    $sccmObj = Get-CMDevice -Name "*$($computer)*" | Where-Object {$_.Name -match "$($computer)[a-z]{2}$"}
    #############################################################################################################################
    # Check for an AD Object
    if ($adObj) {
        $computerLog.HostName = $adObj
        Log "   - Found Hostname in Active Directory: $($adObj)"
        Write-Host "Found Hostname in Active Directory: $($adObj)" -ForegroundColor Green
        
        try {
            Remove-ADComputer -Identity $adObj -Credential $credential -Confirm:$false -ErrorAction Stop 
            $computerLog.ADRemoved = $date
            Log "   - Removed object from Active Directory: $($adObj)"
            Write-Host "Removed object from Active Directory: $($adObj)" -ForegroundColor Green
        }
        catch {
            $computerLog.ADRemoved = "Error $($date)"
            Log "   - Unknown Error - Unable to remove object from Active Directory: $($adObj)"
            Write-Host "Unknown Error - Unable to remove object from Active Directory: $($adObj))" -ForegroundColor Red
        }
        
        $computerLog.EDRGuid = getGUID($adObj)
        $computerLog.EDRRemoved = DeleteGUID($computerLog.EDRGuid)

        $computerLog.SCCMRemoved = deleteSCCM($adObj)
    }
    #############################################################################################################################
    # No AD Object, Check Inventory Sheet
    elseif ($null -eq $computerLog.HostName -and ($invObj)){
        Log "   - Found Hostname in the Invetory Sheet: $($invObj.Name)"
        Write-Host "Found Hostname in the Invetory Sheet: $($invObj.Name)" -ForegroundColor Green
        $computerLog.HostName   = $invObj.Name 
        $computerLog.ADRemoved  = "Checked: $($date)"
        
        $computerLog.EDRGuid = getGUID($invObj.Name)
        $computerLog.EDRRemoved = DeleteGUID($computerLog.EDRGuid)

        $computerLog.SCCMRemoved = deleteSCCM($invObj.Name)
    }
    #############################################################################################################################
    # No AD Object, NOT in Inventory Sheet, Check SCCM
    elseif ($null -eq $computerLog.HostName -and $($sccmObj)) {
        $computerLog.ADRemoved = "Checked: $($date)"
        $computerLog.HostName = $sccmObj.Name
        Log "   - Found Hostname in SCCM: $($sccmObj.Name)"
        Write-Host "Found Hostname in SCCM: $($sccmObj.Name)" -ForegroundColor Green
        
        $computerLog.EDRGuid = getGUID($sccmObj.Name)
        $computerLog.EDRRemoved = DeleteGUID($computerLog.EDRGuid)

        $computerLog.SCCMRemoved = deleteSCCM($sccmObj.Name)
    }
    #############################################################################################################################
    # No AD Object, NOT in Inventory Sheet, and Not in SCCM
    else {
       if ($null -eq $computerLog.HostName)  {
            Log "   - Hostname not found for: $($computer)"
            Write-Host "Hostname not found for: $($computer)" -ForegroundColor DarkYellow
            $computerLog.HostName       = "Hostname not Found"
            $computerLog.EDRGuid        = "N/A"
            $computerLog.ADRemoved      = "Checked: $($date)"
            $computerLog.SCCMRemoved    = "Checked: $($date)"
            $computerLog.EDRRemoved     = "N/A"
        }
    #############################################################################################################################
    }
    $computerLog | Export-Csv -Path "$PSScriptRoot\log_$($date)_2.csv" -Append -NoTypeInformation
}
   
# Finally export the updated AD Inventory for next Dispo
#Get-ADComputer -Filter { Name -Like "*" } | Export-Csv  -Path $PSScriptRoot\ADInventory.csv -NoTypeInformation
    

