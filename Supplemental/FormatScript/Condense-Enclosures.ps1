function Condense-Enclosures {
    [CmdletBinding()]
    param(
        [parameter(Position=0, ValueFromPipeline=$true, HelpMessage='Lines of code to look for and condense.')]
        [string[]]$Code,
        [parameter(Position=1, HelpMessage='Start of enclosure (typically left parenthesis or curly braces')]
        [string[]]$EnclosureStart = @('{','(','@{')
    )
    begin {
        $Codeblock = @()
        $enclosures = @()
        $EnclosureStart | foreach {$enclosures += [Regex]::Escape($_)}
        $regex = '^\s*('+ ($enclosures -join '|') + ')\s*$'
        $Output = @()
        $Count = 0
        $LineCount = 0
    }
    process {
        $Codeblock += $Code
    }
    end {
        $Codeblock | Foreach {
            $LineCount++
            if (($_ -match $regex) -and ($Count -gt 0)) {
                $Output[$Count - 1] = "$($Output[$Count - 1]) $($Matches[1])"
                Write-Verbose "Condense-Enclosures: Condensed enclosure $($Matches[1]) at line $LineCount"
            }
            else {
                $Output += $_
                $Count++
            }
        }
        $Output
    }
}

function Convert-KeywordsAndOperatorsToLower {
    [CmdletBinding()]
    param(
        [parameter(Position=0, ValueFromPipeline=$true, HelpMessage='Lines of code to look for and condense.')]
        [string[]]$Code
    )
    begin {
        $Codeblock = @()
        $Output = @()
    }
    process {
        $Codeblock += $Code
    }
    end {
        $Codeblock = $Codeblock | Out-String

        $ScriptBlock = [Scriptblock]::Create($Codeblock)
        [Management.Automation.PSParser]::Tokenize($ScriptBlock, [ref]$null) | 
        Where {($_.Type -eq 'keyword') -or ($_.Type -eq 'operator') -and (($_.Content).length -gt 1)} | 
        Foreach {
            $Convert = $false
            if (($_.Content -match "^-{1}\w{2,}$") -and ($_.Content -cmatch "[A-Z]") -and ($_.Type -eq 'operator') -or 
               (($_.Type -eq 'keyword') -and ($_.Content -cmatch "[A-Z]"))) {
                $Convert = $true
            }
            if ($Convert) {
                Write-Verbose "Convert-KeywordsAndOperatorsToLower: Converted keyword $($_.Content) at line $($_.StartLine)"
                $Codeblock = $Codeblock.Remove($_.Start,$_.Length)
                $Codeblock = $Codeblock.Insert($_.Start,($_.Content).ToLower())
            }
        }

        return $Codeblock
    }
}

function Pad-Operators {
    [CmdletBinding()]
    param(
        [parameter(Position=0, ValueFromPipeline=$true, HelpMessage='Lines of code to look for and condense.')]
        [string[]]$Code,
        [parameter(Position=1, HelpMessage='Operator(s) to validate single spaces are around.')]
        [string[]]$Operators = @('=','+=','-=')
    )
    begin {
        $Codeblock = @()
        $ops = @()
        $Operators | foreach {$ops += [Regex]::Escape($_)}
        $Output = ''
        $LineCount = 0
        $regex = '((\s*)(' + ($ops -join '|') + ')(\s*))'
    }
    process {
        $Codeblock += $Code
    }
    end {
        $Codeblock | Foreach {
            $LineCount++
            $Output = $_
            if ($_ -match $regex) {
                Write-Verbose "Operator Found on line $($LineCount): $($Matches[3])"
                if (($Matches[2].length -ne 1) -or ($Matches[4].length -ne 1)) {
                    $Output = $_ -replace $Matches[0],(' ' + $Matches[3] + ' ')
                    Write-Verbose '-->Operator padding corrected!'
                }
            }
            $Output
        }
    }
}

$test = Get-Content 'C:\Users\Zachary\Dropbox\Zach_Docs\Projects\Scripts\Get-GeneralSystemReport\New\Finished\Get-RemoteInstalledPrograms.ps1'
#$Codeblock = $test | Out-String
#$ScriptBlock = [Scriptblock]::Create($Codeblock)
#$SB2 = [Management.Automation.PSParser]::Tokenize($ScriptBlock, [ref]$null) 
#$test2 = $test | Condense-Enclosures -Verbose
$test3 = $test | Pad-Operators -verbose | Condense-Enclosures -Verbose | Convert-KeywordsAndOperatorsToLower -Verbose
$test3 | clip
#$test | Pad-Operators -Verbose
#$test2 | clip
#$test = Get-Content -Path 'C:\Users\Zachary\Dropbox\Zach_Docs\Projects\Git\Powershell\OS\Multiple Runspace\Get-RemoteShadowCopyInformation.ps1' -Raw
#$ScriptBlock = [Scriptblock]::Create($test)

# Tokenize the script
#$tokens = [Management.Automation.PSParser]::Tokenize($ScriptBlock, [ref]$null) #| Where {$_.Type -ne 'NewLine'}
#$a = Get-FunctionParameters -ScriptBlock $test