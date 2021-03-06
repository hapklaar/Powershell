﻿function Search-AD {
    # Original Author (largely unmodified btw): 
    #  http://becomelotr.wordpress.com/2012/11/02/quick-active-directory-search-with-pure-powershell/
    [CmdletBinding()]
    param (
        [string[]]$Filter,
        [string[]]$Properties = @('Name','ADSPath'),
        [string]$SearchRoot='',
        [switch]$DontJoinAttributeValues,
        [System.DirectoryServices.DirectoryEntry]$DirectoryEntry = $null
    )

    if ($DirectoryEntry -ne $null) {
        if ($SearchRoot -ne '') {
            $DirectoryEntry.set_Path($SearchRoot)
        }
    }
    else {
        $DirectoryEntry = [System.DirectoryServices.DirectoryEntry]$SearchRoot
    }

    if ($Filter) {
        $LDAP = "(&({0}))" -f ($Filter -join ')(')
    }
    else {
        $LDAP = "(name=*)"
    }
    try {
        (New-Object System.DirectoryServices.DirectorySearcher -ArgumentList @(
            $DirectoryEntry,
            $LDAP,
            $Properties
        ) -Property @{
            PageSize = 1000
        }).FindAll() | ForEach-Object {
            $ObjectProps = @{}
            $_.Properties.GetEnumerator() |
                Foreach-Object {
                    $Val = @($_.Value)
                    if ($_.Name -ne $null) {
                        if ($DontJoinAttributeValues -and ($Val.Count -gt 1)) {
                            $ObjectProps.Add($_.Name,$_.Value)
                        }
                        else {
                            $ObjectProps.Add($_.Name,(-join $_.Value))
                        }
                    }
                }
            if ($ObjectProps.psbase.keys.count -ge 1) {
                New-Object PSObject -Property $ObjectProps | Select $Properties
            }
        }
    }
    catch {
        Write-Warning -Message ('Search-AD: Filter - {0}: Root - {1}: Error - {2}' -f $LDAP,$Root.Path,$_.Exception.Message)
    }
}
