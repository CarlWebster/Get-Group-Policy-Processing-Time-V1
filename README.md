# GetGPOProcessingTime
Gets the average, minimum and maximum Group Policy processing time on  computers in Microsoft Active Directory.

	Gets the average, minimum and maximum Group Policy processing time on XenApp 6.5 servers.

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
