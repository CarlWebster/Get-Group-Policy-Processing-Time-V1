<#
.SYNOPSIS
	Gets the average, minimum and maximum Group Policy processing time on XenApp 6.5 servers.
.DESCRIPTION
	Builds a list of all XenApp 6.5 servers in a Farm.
	Process each server looking in the Microsoft-Windows-GroupPolicy/Operational for all Event ID 8001.
	Displays the Avergage, Minimum and Maximum processing times.
	
	All events where processing time is 0 are ignored. A 0 time means a local account was used for login.
	
	There is a bug with Get-WinEvent and PowerShell versions later than 2 or culture other than en-US,
	the Message property is not returned.

	There are two work-arounds:
	1. PowerShell.exe -Version 2
	2. Add this line to the script: 
	[System.Threading.Thread]::CurrentThread.CurrentCulture = New-Object "System.Globalization.CultureInfo" "en-US"
	
.PARAMETER MaxSeconds
	Specifies the number of seconds to use for the cutoff for GPO processing time.
	Any value greater than or equal to MaxSeconds is recorded along with the user name and server name.
	Default is 30.
.PARAMETER Folder
	Specifies the optional output folder to save the output reports. 
.EXAMPLE
	PS C:\PSScript > .\Get-GPOTimeV1.1.ps1
.EXAMPLE
	PS C:\PSScript > .\Get-GPOTimeV1.1.ps1 -Folder \\ServerName\Share
	
	Saves the two output text files in \\ServerName\Share.
.EXAMPLE
	PS C:\PSScript > .\Get-GPOTimeV1.1.ps1 -MaxSeconds 10
	
	When the total group policy processing time is greater than or equal 10 seconds,
	the time, user name and server name are recorded in LongGPOTimes.txt.
.EXAMPLE
	PS C:\PSScript > .\Get-GPOTimeV1.1.ps1 -MaxSeconds 17 -Folder c:\LogFiles
	
	When the total group policy processing time is greater than or equal 17 seconds,
	the time, user name and server name are recorded in LongGPOTimes.txt.
	
	Saves the two output text files in C:\LogFiles.
.INPUTS
	None.  You cannot pipe objects to this script.
.OUTPUTS
	No objects are output from this script.
	The script creates two text files:
		LongGPOTimes.txt
		GPOAvgMinMaxTimes.txt
		
	By default, the two text files are stored in the folder where the script is run.
.NOTES
	NAME: Get-GPOTime.ps1
	VERSION: 1.1
	AUTHOR: Carl Webster
	LASTEDIT: March 24, 2016
#>


#Created by Carl Webster, CTP and independent consultant 05-Mar-2016
#webster@carlwebster.com
#@carlwebster on Twitter
#http://www.CarlWebster.com

[CmdletBinding(SupportsShouldProcess = $False, ConfirmImpact = "None", DefaultParameterSetName = "Default") ]

Param(
	[parameter(ParameterSetName="Default",Mandatory=$False)] 
	[Int]$MaxSeconds = 30,

	[parameter(ParameterSetName="Default",Mandatory=$False)] 
	[string]$Folder=""
	
	)

#Version 1.1 24-Mar-2016
#	Allows you to specify the maximum number of seconds group policy processing should take. Any number greater than or equal to that number is recorded in LongGPOTimes.txt.
#	Allows you to specify an output folder.
#	Records the long GPO times in an text file.
#	Records the Average, Minimum and Maximum processing time to GPOAvgMinMaxTimes.txt.
#	GPOAvgMinMaxTimes.txt is a cumulative file and records the Average, Minimum and Maximum times for each run of the script.

Write-Host "$(Get-Date): Setting up script"

If($MaxSeconds -eq $Null)
{
	$MaxSeconds = 30
}
If($Folder -eq $Null)
{
	$Folder = ""
}

If(!(Test-Path Variable:Seconds))
{
	$MaxSeconds = 30
}
If(!(Test-Path Variable:Folder))
{
	$Folder = ""
}

If($Folder -ne "")
{
	Write-Host "$(Get-Date): Testing folder path"
	#does it exist
	If(Test-Path $Folder -EA 0)
	{
		#it exists, now check to see if it is a folder and not a file
		If(Test-Path $Folder -pathType Container -EA 0)
		{
			#it exists and it is a folder
			Write-Host "$(Get-Date): Folder path $Folder exists and is a folder"
		}
		Else
		{
			#it exists but it is a file not a folder
			Write-Error "Folder $Folder is a file, not a folder.  Script cannot continue"
			Exit
		}
	}
	Else
	{
		#does not exist
		Write-Error "Folder $Folder does not exist.  Script cannot continue"
		Exit
	}
}

If($Folder -eq "")
{
	$pwdpath = $pwd.Path
}
Else
{
	$pwdpath = $Folder
}

If($pwdpath.EndsWith("\"))
{
	#remove the trailing \
	$pwdpath = $pwdpath.SubString(0, ($pwdpath.Length - 1))
}

[string]$FileName1 = "$($pwdpath)\LongGPOTimes.txt"
[string]$FileName2 = "$($pwdpath)\GPOAvgMinMaxTimes.txt"

Function Check-NeededPSSnapins
{
	Param([parameter(Mandatory = $True)][alias("Snapin")][string[]]$Snapins)

	#Function specifics
	$MissingSnapins = @()
	[bool]$FoundMissingSnapin = $False
	$LoadedSnapins = @()
	$RegisteredSnapins = @()

	#Creates arrays of strings, rather than objects, we're passing strings so this will be more robust.
	$loadedSnapins += Get-pssnapin | % {$_.name}
	$registeredSnapins += Get-pssnapin -Registered | % {$_.name}

	ForEach($Snapin in $Snapins)
	{
		#check if the snapin is loaded
		If(!($LoadedSnapins -like $snapin))
		{
			#Check if the snapin is missing
			If(!($RegisteredSnapins -like $Snapin))
			{
				#set the flag if it's not already
				If(!($FoundMissingSnapin))
				{
					$FoundMissingSnapin = $True
				}
				#add the entry to the list
				$MissingSnapins += $Snapin
			}
			Else
			{
				#Snapin is registered, but not loaded, loading it now:
				Write-Host "$(Get-Date): Loading Windows PowerShell snap-in: $snapin"
				Add-PSSnapin -Name $snapin -EA 0
			}
		}
	}

	If($FoundMissingSnapin)
	{
		Write-Warning "Missing Windows PowerShell snap-ins Detected:"
		$missingSnapins | % {Write-Warning "($_)"}
		Return $False
	}
	Else
	{
		Return $True
	}
}

Write-Host "$(Get-Date): Loading XenApp snapin"
If(!(Check-NeededPSSnapins "Citrix.XenApp.Commands"))
{
	#We're missing Citrix Snapins that we need
	$ErrorActionPreference = $SaveEAPreference
	Write-Error "Missing Citrix PowerShell Snap-ins Detected, check the console above for more information. Script will now close."
	Exit
}

[bool]$Remoting = $False
$RemoteXAServer = Get-XADefaultComputerName -EA 0 
If(![String]::IsNullOrEmpty($RemoteXAServer))
{
	$Remoting = $True
}

If($Remoting)
{
	Write-Host "$(Get-Date): Remoting is enabled to XenApp server $RemoteXAServer"
	#now need to make sure the script is not being run against a session-only host
	$Server = Get-XAServer -ServerName $RemoteXAServer -EA 0 
	If($Server.ElectionPreference -eq "WorkerMode")
	{
		$ErrorActionPreference = $SaveEAPreference
		Write-Warning "This script cannot be run remotely against a Session-only Host Server."
		Write-Warning "Use Set-XADefaultComputerName XA65ControllerServerName or run the script on a controller."
		Write-Error "Script cannot continue.  See messages above."
		Exit
	}
}
Else
{
	Write-Host "$(Get-Date): Remoting is not used"
	
	#now need to make sure the script is not being run on a session-only host
	$ServerName = (Get-Childitem env:computername).value
	$Server = Get-XAServer -ServerName $ServerName -EA 0
	If($Server.ElectionPreference -eq "WorkerMode")
	{
		$ErrorActionPreference = $SaveEAPreference
		Write-Warning "This script cannot be run on a Session-only Host Server if Remoting is not enabled."
		Write-Warning "Use Set-XADefaultComputerName XA65ControllerServerName or run the script on a controller."
		Write-Error "Script cannot continue.  See messages above."
		Exit
	}
}

$startTime = Get-Date

Write-Host "$(Get-Date): Getting XenApp servers"
$servers = Get-XAServer -ea 0 | Select ServerName | Sort ServerName

If($? -and $Null -ne $servers)
{
	If($servers -is [Array])
	{
		[int]$Total = $servers.count
	}
	Else
	{
		[int]$Total = 1
	}
	Write-Host "$(Get-Date): Found $($Total) XenApp servers"
	$TimeArray = @()
	$LongGPOsArray = @()
	$cnt = 0
	ForEach($server in $servers)
	{
		$cnt++
		Write-Host "$(Get-Date): Processing server $($Server.ServerName) $($Total - $cnt) left"
		If(Test-Connection -ComputerName $server.servername -quiet -EA 0)
		{
			try
			{
				$GPTime = Get-WinEvent -logname Microsoft-Windows-GroupPolicy/Operational `
				-computername $server.servername | Where {$_.id -eq "8001"} | Select message
			}
			
			catch
			{
				Write-Host "$(Get-Date): `tServer $($Server.ServerName) had error being accessed"
				Continue
			}
			
			If($? -and $Null -ne $GPTime)
			{
				ForEach($GPT in $GPTime)
				{
					$tmparray = $GPT.Message.ToString().Split(" ")
					[int]$GPOTime = $tmparray[8]
					If($GPOTime -ne 0)
					{
						$TimeArray += $GPOTime
					}
					If($GPOTime -ge $MaxSeconds)
					{
						$obj = New-Object -TypeName PSObject
						$obj | Add-Member -MemberType NoteProperty -Name MaxSeconds	-Value $GPOTime
						$obj | Add-Member -MemberType NoteProperty -Name User		-Value $tmparray[6]
						$obj | Add-Member -MemberType NoteProperty -Name Server		-Value $server.servername
						$LongGPOsArray += $obj
					}
					
				}
			}
		}
		Else
		{
			Write-Host "$(Get-Date): `tServer $($Server.ServerName) is not online"
		}
	}
	
	Write-Host "$(Get-Date): Output long GPO times to file"
	#first sort array by seconds, longest to shortest
	$LongGPOsArray = $LongGPOsArray | Sort MaxSeconds -Descending
	Out-File -FilePath $Filename1 -InputObject $LongGPOsArray

	If(Test-Path "$($FileName1)")
	{
		Write-Host "$(Get-Date): $($FileName1) is ready for use"
	}

	$Avg = ($TimeArray | Measure-Object -Average -minimum -maximum)
	Write-Host "Average: " $Avg.Average
	Write-Host "Minimum: " $Avg.Minimum
	Write-Host "Maximum: " $Avg.Maximum

	Write-Host "$(Get-Date): Output GPO Avg/Min/Max times to file"
	Out-File -FilePath $Filename2 -Append -InputObject " "
	Out-File -FilePath $Filename2 -Append -InputObject "$(Get-Date): Average: $($Avg.Average) seconds"
	Out-File -FilePath $Filename2 -Append -InputObject "$(Get-Date): Minimum: $($Avg.Minimum) seconds"
	Out-File -FilePath $Filename2 -Append -InputObject "$(Get-Date): Maximum: $($Avg.Maximum) seconds"
	Out-File -FilePath $Filename2 -Append -InputObject " "

	If(Test-Path "$($FileName2)")
	{
		Write-Host "$(Get-Date): $($FileName2) is ready for use"
	}
}
ElseIf($? -and $Null -eq $servers)
{
	Write-Warning "Server information could not be retrieved"
}
Else
{
	Write-Warning "No results returned for Server information"
}

Write-Host "$(Get-Date): Script started: $($StartTime)"
Write-Host "$(Get-Date): Script ended: $(Get-Date)"
$runtime = $(Get-Date) - $StartTime
$Str = [string]::format("{0} days, {1} hours, {2} minutes, {3}.{4} seconds", `
	$runtime.Days, `
	$runtime.Hours, `
	$runtime.Minutes, `
	$runtime.Seconds,
	$runtime.Milliseconds)
Write-Host "$(Get-Date): Elapsed time: $($Str)"
$runtime = $Null
