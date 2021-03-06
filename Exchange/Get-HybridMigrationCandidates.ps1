﻿<#
.SYNOPSIS
Determine mailboxes to migrate to o365 in one group based on their full access permission relationships to one another.

.DESCRIPTION
Determine mailboxes to migrate to o365 in one group based on their full access permission relationships to one another. This is meant to be run
multiple times against several seeduser accounts to help determine what groups of accounts you would want to migrate together. The first
time this is run a few global variables are populated in order to reduce the processing required in future itterations.

If you run this script without any seeduser specified then all mailboxes which no others have full access to and that are not accessing 
other mailboxes via full access permission will be listed. These are the 'low hanging fruit' and generally can be migrated at any time.

.PARAMETER SeedUser
Specifying the seeduser mailbox asks the question, If you were to migrate this mailbox, which others would need to be migrated as well?
If this parameter is not specified then only mailboxes without any full access permission relationships are returned in the report.

.PARAMETER Domain
Short domain name. This is used as permissions to mailboxes are returned as '<DOMAIN>\<Username>'. If unspecified the local domain is used.

.PARAMETER AdditionalUserFilters
An array of user IDs which are ignored in the mailbox relationship calculations. These filters are extremely important to specify as one admin user mailbox
with access to every mailbox in the environment will mean that every single mailbox is associated as one group if it is not filtered ahead of time!

.LINK
http://www.the-little-things.net

.NOTES
Version
    1.0.0 04/01/2016
    - Initial release
Author
    Zachary Loeber

.EXAMPLE
$AdminIgnoreAccts = @(
    '*\admin-*',
    '*\someadminuser',
    '*\VeritasService'
)
.\Get-MailboxFullAccessPermission.ps1 -AdditionalUserFilters $AdminIgnoreAccts

Description
-----------
Generate a default report on the low hanging fruit for an initial migration. Filter out any results including $AdminIgnoreAccts

#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "A seed user to base permission checks upon. If not defined then only unshared singular mailboxes will be validated.")]
    [string]$SeedUser,
    [Parameter(Position = 1, HelpMessage = "Short domain name")]
    [string]$Domain,
    [Parameter(Position = 2, HelpMessage = "Additional user filters")]
    [string[]]$AdditionalUserFilters = @()
)

function Get-MailboxFullAccessPermission {
    <#
    .SYNOPSIS
    Retrieves a list of mailbox full access permissions
    .DESCRIPTION
    Gathers a list of users with full access permissions for a mailbox.
    .PARAMETER MailboxNames
    Array of mailbox names in string format.    
    .PARAMETER MailboxObject
    One or more mailbox objects.
    .PARAMETER ShowAll
    Includes unresolved names (typically deleted accounts).
    .PARAMETER Expand
    Expands results
    .PARAMETER AdditionalUserFilters
    Additional user filters
    .PARAMETER ExpandGroups
    Tests each permission to determine if it is a group and expands it.
    .PARAMETER IncludeNullResults
    Includes mailboxes with all full permissions filtered out. This can be useful for finding mailboxes which are not shared.

    .LINK
    http://www.the-little-things.net   
    .NOTES
    Version
        1.0.0 01/25/2016
        - Initial release
    Author      :   Zachary Loeber

    .EXAMPLE
    Get-MailboxFullAccessPermission -MailboxName "Test User1" -Verbose

    Description
    -----------
    Gets the send-as permissions for "Test User1" and shows verbose information.

    .EXAMPLE
    Get-MailboxFullAccessPermission -MailboxName 'user1' | Format-List

    Description
    -----------
    Gets the send-as permissions for "user1" and returns the info as a format-list.
    
    .EXAMPLE
    $AdditionalUserFilters = @(
        '*\user-admin',
        '*\somearchivingsolutionaccount',
        '*\someoldbackupaccount',
        '*\unifiedmessagingadmin'
    )
    
    $Domain = 'CONTOSO'     # The domain short name (ie. DOMAIN\<username>)
    $perms = Get-Mailbox -ResultSize Unlimited | Get-MailboxFullAccessPermission -AdditionalUserFilters $AdditionalUserFilters -expand -expandgroup -verbose -IncludeNullResults
    $groups = $perms | Sort-Object -Property FullAccess | Group-Object -Property FullAccess -AsString -AsHashTable
    
    $standalonemailboxes = @()
    Write-Host -ForegroundColor Green "The following mailboxes have full permissions on no other mailboxes." 
    Write-Host -ForegroundColor Green "Additionally, no other mailboxes have full access to these mailboxes."
    $perms | Where {$_.FullAccess -eq $null} | Foreach {
        $tmp = "$($Domain)\" + $_.MailboxAlias
        if (($groups.$tmp).Count -eq 0) {
            Write-Host -ForegroundColor Green "    $($_.Mailbox)"
            $standalonemailboxes += $_.Mailbox
        }
    }

    Description
    -----------
    Queries all mailboxes full permission access and filters out results using the default filters plus several custom filters and stores the results in $perm.
    The -expandgroup flag attempts to expand out full access users from groups that may be assigned to mailboxes. IncludeNullResults includes mailboxes for which
    all full access permissions have been filtered out. The expand flag returns one entry for every user. Then we output to the screen all the users which
    in the permissions list along with a count of mailboxes for which they have full access and save the results to $standalonemailboxes.

    #>
    [CmdLetBinding(DefaultParameterSetName='AsString')]
    param(
        [Parameter(ParameterSetName='AsString', Mandatory=$True, ValueFromPipeline=$True, Position=0, HelpMessage="Enter an Exchange mailbox name")]
        [string]$MailboxName,
        [Parameter(ParameterSetName='AsMailbox', Mandatory=$True, ValueFromPipeline=$True, Position=0, HelpMessage="Enter an Exchange mailbox name")]
        [Microsoft.Exchange.Data.Directory.Management.Mailbox]$MailboxObject,
        [Parameter(HelpMessage='Includes unresolved and other common full permission accounts.')]
        [switch]$ShowAll,
        [Parameter(HelpMessage="Additional user filters")]
        [string[]]$AdditionalUserFilters = @(),
        [Parameter(HelpMessage='Expands results.')]
        [switch]$Expand,
        [Parameter(HelpMessage='Expands AD groups.')]
        [switch]$ExpandGroups,
        [Parameter(HelpMessage='Includes mailboxes with all full permissions filtered out.')]
        [switch]$IncludeNullResults
    )
    begin {
        $FunctionName = $FunctionName
        Write-Verbose "$($FunctionName): Begin"
        $Mailboxes = @()
        if (-not $ShowAll) {
            # These are some standard user exceptions you may find in your environment
            # You can supply your own list by including -ShowAll and -AdditionalUserFilters
            # in the same call.
            $UserExceptions = @(
                'S-1-*',
                "*\Organization Management",
                "*\Domain Admins",
                "*\Enterprise Admins",
                "*\Exchange Services",
                "*\Exchange Trusted Subsystem",
                "*\Exchange Servers",
                "*\Exchange View-Only Administrators",
                "*\Exchange Admins",
                "*\Managed Availability Servers",
                "*\Public Folder Administrators",
                "*\Exchange Domain Servers",
                "*\Exchange Organization Administrators",
                "NT AUTHORITY\*")
        }
        else {
            $UserExceptions = @()
        }
        $UserExceptions += $AdditionalUserFilters
        
        if ($UserExceptions.Count -gt 0) {
            # If we have some user exceptions create one big regex to filter against later
            $ExceptionMatches = @($UserExceptions | Foreach {[regex]::Escape($_)})
            $Exceptions = '^(' + ($ExceptionMatches -join '|') + ')$'
            
            # The regex escape will turn '*' into '\*', this next statment turns it into a match all regex of '.*'
            $Exceptions = $Exceptions -replace '\\\*','.*'
        }
        else {
            # If there are no exceptions this will fail to match anything and thus allow all results to be processed.
            $Exceptions = '^()$'
        }
        Write-Verbose "$($FunctionName): Exceptions regex string - $exceptions"
    }
    process {
        switch ($PSCmdlet.ParameterSetName) {
            'AsStringArray' {
                try {
                    $Mailboxes += Get-Mailbox $MailboxName -erroraction Stop
                }
                catch {
                    Write-Warning = "$($FunctionName): $_.Exception.Message"
                }
            }
            'AsMailbox' {
               $Mailboxes += @($MailboxObject)
            }
        }
    }
    end {
        ForEach ($Mailbox in $Mailboxes) {
            Write-Verbose "$($FunctionName): Processing Mailbox $($Mailbox.Name)"
            
            # Initiate our array for this one mailbox to store all the full access users we end up enumerating.
            $FullAccessUsers = @()
            
            # Get all the full access permissions on a mailbox where it is not set to 'denied'
            $fullperms = @($Mailbox | Get-MailboxPermission | Where {($_.AccessRights -like "*FullAccess*") -and (-not $_.Deny)})
            
            # If we have results then continume processing
            if ($fullperms.Count -gt 0) {
                $fullperms | Foreach {
                    # Foreach permission found see if it gets filtered out in our exception list.
                    if ($_.User.RawIdentity -notmatch $Exceptions) {
                        if ($ExpandGroups) {
                            if ($_.User.RawIdentity -match '^(.*\\)(.*)$') {
                                $domstring = $matches[1]
                                $grpstring = $matches[2]
                            }
                            else {
                                $domstring = ''
                                $grpstring = $_.User.RawIdentity
                            }
                            
                            try {
                                $groupmembers = @(Get-ADGroupMember $grpstring -Recursive)
                            }
                            catch {
                                $groupmembers = $null
                            }
                            if ($groupmembers -ne $null) {
                                Write-Verbose "$($FunctionName): $grpstring is a group with $($groupmembers.count) members..."
                                #foreach ($groupmember in $groupmembers) {
                                
                                ($groupmembers).SamAccountName | Foreach {
                                    $memberusername = "$($domstring)$($_)"
                                    if ($memberusername -notmatch $Exceptions) {
                                        $FullAccessUsers += $memberusername
                                    }
                                }
                            }
                            else {
                                Write-Verbose "$($FunctionName): $($_.User.RawIdentity) is a non-filtered user"
                                $FullAccessUsers += $_.User.RawIdentity
                            }
                        }
                        else {
                            $FullAccessUsers += $_.User.RawIdentity
                        }
                    }
                }
                if (($FullAccessUsers.Count -gt 0) -or ($IncludeNullResults)) {
                    $NewObjProp = @{
                        'Mailbox' = $Mailbox.Name
                        'MailboxEmail' = $Mailbox.PrimarySMTPAddress
                        'MailboxAlias' = $Mailbox.Alias
                        'FullAccess' = $null
                    }
                    $FullAccessUsers = $FullAccessUsers | Select -Unique
                    
                    if ($Expand) {
                        if ($FullAccessUsers.Count -eq 0) {
                            New-Object psobject -Property $NewObjProp
                        }
                        else {
                            $FullAccessUsers | Foreach {
                                $NewObjProp.FullAccess = $_
                                New-Object psobject -Property $NewObjProp
                            }
                        }
                    }
                }
                else {
                    if ($FullAccessUsers.Count -eq 0) {
                        New-Object psobject -Property $NewObjProp
                    }
                    else {
                        $NewObjProp.FullAccess = $FullAccessUsers
                        New-Object psobject -Property $NewObjProp
                    }
                }
            }
        }
        Write-Verbose "$($FunctionName): End"
    }
}

if ([string]::IsNullOrEmpty($Domain)) {
    $tmp = (Get-WmiObject Win32_NTDomain).DomainName
    $tmp = [string]$tmp
    $Domain = $tmp.Trim()
    Write-Host -ForegroundColor Yellow "Domain parameter not provided, so we are using $($Domain) instead.."
}
if (($global:Mailboxes).Count -eq 0) {
    Write-Host -ForegroundColor:Cyan 'Getting all your organization mailboxes. Hang tight, this will likely take some time to complete...'
    $global:Mailboxes = Get-mailbox -resultsize Unlimited
}
else {
    Write-Host -ForegroundColor:Cyan 'The global mailboxes variable seems to be already populated, skipping this portion of the script.'
    Write-Host -ForegroundColor:Cyan 'If you want to start from scratch nullify this variable with the following statement:'
    Write-Host -ForegroundColor:Cyan '    $global:Mailboxes = $null'
    Write-Host ''
    Write-Host 'Press any key to continue...'
    pause
}

if (($global:Perms).Count -eq 0) {
    Write-Host -ForegroundColor:Cyan 'Enumerating mailbox permissions. Hang tight, this will likely take some time to complete...'
    $global:Perms = $global:Mailboxes | Get-MailboxFullAccessPermission -AdditionalUserFilters $AdditionalUserFilters -expand -expandgroup -IncludeNullResults
}
else {
    Write-Host -ForegroundColor:Cyan 'The global Perms variable seems to be already populated, skipping this portion of the script.'
    Write-Host -ForegroundColor:Cyan 'If you want to start from scratch nullify this variable with the following statement:'
    Write-Host -ForegroundColor:Cyan '    $global:Perms = $null'
    Write-Host ''
    Write-Host 'Press any key to continue...'
}

# Filter out permissions where there is no matching mailbox
$MailboxAliases = @(($global:Mailboxes).Alias | Foreach {"$($Domain)\$($_)"})
$FilteredPerms = $global:Perms | Where {$MailboxAliases -contains $_.FullAccess}

# get the assigned permissions by user
$groups = $FilteredPerms | Sort-Object -Property FullAccess | Group-Object -Property FullAccess -AsString -AsHashTable

if ([string]::IsNullOrEmpty($SeedUser)) {
    $standalonemailboxes = @()
    Write-Host -ForegroundColor Green "The following mailboxes do NOT have any full access permissions on other mailboxes." 
    Write-Host -ForegroundColor Green "(Additionally, no other mailboxes have full access to these either.)"
    $global:Perms | Where {$_.FullAccess -eq $null} | Foreach {
        $tmp = "$($Domain)\" + $_.MailboxAlias
        if (($groups.$tmp).Count -eq 0) {
            Write-Host -ForegroundColor Green "    $($_.Mailbox)"
            $standalonemailboxes += $_.Mailbox
        }
    }
}

else {
    try {
        $seeduseralias = ($global:Mailboxes | Where {$_.Name -eq $seeduser})[0].Alias
    }
    catch {
        Write-Host -ForegroundColor Red "The seed user does not appear to have a mailbox, exiting script!"
        return
    }

    $Global:MailboxesToMigrate = @()
    $MailboxesToCheck = @($seeduseralias)
    $checkedMailboxes = @()

    $Iteration = 0
    Do {
        $Iteration++
        $tempmailbox = @()
        $currentmailbox = $MailboxesToCheck[0]
        $checkedMailboxes += $currentmailbox
        $currmailboxgroupcheck = "$($Domain)\" + $currentmailbox
        $MailboxesToCheck = @()
        
        Write-Host "Checking permissions on $currentmailbox...."
        # Get the mailboxes which have full access to the seed mailbox.
        $mailboxperms = @($FilteredPerms | Where {$_.MailboxAlias -eq $currentmailbox})
        
        if ($mailboxperms.Count -gt 0) {
            Write-Host -ForegroundColor Cyan "...The following users have access to $($currentmailbox):"
            Foreach ($mailbox in ($mailboxperms.FullAccess)) {
                $mbxout = $mailbox -replace "$($Domain)\\",''
                $tempmailbox += $mbxout
                Write-Host -ForegroundColor Yellow "    $mbxout"
                if ($groups.$mailbox -ne $null) {
                    Write-Host -ForegroundColor DarkCyan "    -- Which also have access to the following (only going one level deep):"
                    $groups.$mailbox | Foreach {
                        Write-Host -ForegroundColor DarkCyan "    ----:$($_.Mailbox)"
                        $tempmailbox += $_.MailboxAlias
                    }
                }
            }
        }
        
        Write-Host -ForegroundColor Cyan "$($currentmailbox) itself has access to the following mailboxes:"
        $accessto = $groups.$currmailboxgroupcheck
        $accessto | Foreach {
            Write-Host -ForegroundColor Yellow "    $($_.MailboxAlias)"
            $tempmailbox += $_.MailboxAlias
        }
        
        $tempmailbox = @($tempmailbox | Select -Unique)
        
        $Global:MailboxesToMigrate += @($tempmailbox)

        $Global:MailboxesToMigrate = @($Global:MailboxesToMigrate | Select -Unique)
        $Global:MailboxesToMigrate | foreach {
            if ($checkedMailboxes -notcontains $_) {
                $MailboxesToCheck += $_
            }
        }
        
        Write-Host -ForegroundColor DarkCyan "Iteration #$($Iteration) Complete! The following mailboxes have been checked and will not be checked again:"
        $checkedMailboxes | Foreach { Write-Host -ForegroundColor DarkCyan "    $($_)" }
    } Until ($MailboxesToCheck.Count -eq 0)
    
    $Global:MailboxesToMigrate += $seeduseralias
    $Global:MailboxesToMigrate = $Global:MailboxesToMigrate | Sort | Select -Unique

    Write-Host ''
    Write-Host -ForegroundColor Magenta "Based on your seed mailbox ($seeduser) you should migrate the following mailboxes as one group if possible:"
    $Global:MailboxesToMigrate | Foreach { Write-Host -ForegroundColor Magenta "    $($_)" }
}
