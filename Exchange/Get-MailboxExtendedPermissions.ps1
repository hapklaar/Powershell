function Get-MailboxExtendedRights {
    <#
    .SYNOPSIS
    Retrieves a list of mailbox extended rights.
    .DESCRIPTION
    Get-MailboxExtendedRights gathers a list of extended rights like 'send-as' on exchange mailboxes.
    .PARAMETER MailboxName
    One mailbox name in string format.
    .PARAMETER MailboxName
    Array of mailbox names in string format.    
    .PARAMETER MailboxObject
    One or more mailbox objects.
    .LINK
    http://www.the-little-things.net   
    .NOTES
    Last edit   :   11/04/2014
    Version     :   
        1.1.0 11/04/2014
            - Minor structual changes and input parameter updates
        1.0.0 10/04/2014
    Author      :   Zachary Loeber
    .EXAMPLE
    Get-MailboxExtendedRights -MailboxName "Test User1" -Verbose

    Description
    -----------
    Gets the send-as rights for "Test User1" and shows verbose information.

    .EXAMPLE
    Get-MailboxExtendedRights -MailboxName "user1","user2" | Format-List

    Description
    -----------
    Gets the send-as rights on mailboxes "user1" and "user2" and returns the info as a format-list.

    .EXAMPLE
    (Get-Mailbox -Database "MDB1") | Get-MailboxExtendedRights

    Description
    -----------
    Gets all mailboxes in the MDB1 database and pipes it to Get-MailboxExtendedRights and returns the 
    send-as rights.
    #>
    [CmdLetBinding(DefaultParameterSetName='AsString')]
    param(
        [Parameter(ParameterSetName='AsStringArray', Mandatory=$True, ValueFromPipeline=$True, Position=0, HelpMessage="Enter an Exchange mailbox name")]
        [string[]]$MailboxNames,
        [Parameter(ParameterSetName='AsString', Mandatory=$True, ValueFromPipeline=$True, Position=0, HelpMessage="Enter an Exchange mailbox name")]
        [string]$MailboxName,
        [Parameter(ParameterSetName='AsMailbox', Mandatory=$True, ValueFromPipeline=$True, Position=0, HelpMessage="Enter an Exchange mailbox name")]
        $MailboxObject,
        [Parameter(HelpMessage='Rights to check for.')]
        [string]$Rights="*send-as*",
        [Parameter(HelpMessage='Includes unresolved names (typically deleted accounts).')]
        [switch]$ShowAll
    )
    begin {
        Write-Verbose "$($MyInvocation.MyCommand): Begin"
        $Mailboxes = @()
    }
    process {
        switch ($PSCmdlet.ParameterSetName) {
            'AsStringArray' {
                try {
                    $Mailboxes = @($MailboxNames | Foreach {Get-Mailbox $_ -erroraction Stop})
                }
                catch {
                    Write-Warning = "$($MyInvocation.MyCommand): $_.Exception.Message"
                }
            }
            'AsString' {
                try { 
                    $Mailboxes = @(Get-Mailbox $MailboxName -erroraction Stop)
                }
                catch {
                    Write-Warning = "$($MyInvocation.MyCommand): $_.Exception.Message"
                }
            }
            'AsMailbox' {
               $Mailboxes = @($MailboxObject)
            }
        }

        Foreach ($Mailbox in $Mailboxes)
        {
            Write-Verbose "$($MyInvocation.MyCommand): Processing Mailbox $($Mailbox.Name)"
            $extendedperms = @(Get-ADPermission $Mailbox.identity | `
                             Where {$_.extendedrights -like $Rights} | `
                             Select @{n='Mailbox';e={$Mailbox.Name}},User,ExtendedRights,isInherited,Deny)
            if ($extendedperms.Count -gt 0)
            {
                if ($ShowAll)
                {
                    $extendedperms
                }
                else
                {
                    $extendedperms | Where {$_.Name -notlike 'S-1-*'}
                }
            }
        }
    }
    end {
        Write-Verbose "$($MyInvocation.MyCommand): End"
    }
}