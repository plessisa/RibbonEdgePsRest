<#
    .SYNOPSIS 
      This module allows access to Ribbon SBC Edge via PowerShell using REST API's
	 
	.DESCRIPTION
	  This module allows access to Ribbon SBC Edge via PowerShell using REST API's
	  For  the module to run correctly following pre-requisites should be met:
	  1) PowerShell v3.0
	  2) Ribbon SBC Edge on R3.0 or higher
	  3) Create REST logon credentials (http://www.allthingsuc.co.uk/accessing-sonus-ux-with-rest-apis/)
	
	 
	.NOTES
		Name: RibbonEdge
		Author: Vikas Jaswal (Modality Systems Ltd)
		Additional cmdlets added by: Kjetil Lindløkken
        Additional cmdlets added by: Adrien Plessis
		
		Version History:
		Version 1.0 - 30/11/13 - Module Created - Vikas Jaswal
		Version 1.1 - 03/12/13 - Added new-ux*, restart-ux*, and get-uxresource cmdlets - Vikas Jaswal
		Version 1.2 - 02/10/16 - Added get-uxsipservertable, new-uxsippservertable cmdlets - Kjetil Lindløkken
		Version 1.3 - 02/10/18 - Added get-uxsipprofile, Get-uxsipprofileid, get-uxsipservertableentry cmdlets - Kjetil Lindløkken
		Version 1.4 - 03/10/18 - Added new-uxsipserverentry cmdlet - Kjetil Lindløkken
		Version 1.5 - 03/10/18 - Added optional parameter to the get-uxsipprofile cmdlet to add id directly - Kjetil Lindløkken
		Version 1.6 - 04/10/18 - Added new-uxsipprofile cmdlet - Kjetil Lindløkken
        Version 1.7 - 20/12/18 - Match Ribbon rebranding, Update link to Ribbon Docs - Adrien Plessis
		
		Please use the script at your own risk!
	
	.LINK
		http://www.allthingsuc.co.uk
     
  #>

#Ignore SSL, without this GET commands dont work with SBC Edge
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

Function global:connect-uxgateway {
	<#
	.SYNOPSIS      
	 This cmdlet connects to the Ribbon SBC and extracts the session token.
	 
	.DESCRIPTION
	This cmdlet connects to the Ribbon SBC and extracts the session token required for subsequent cmdlets.All other cmdlets will fail if this command is not successfully executed.
	
	.PARAMETER uxhostname
	Enter here the hostname or IP address of the Ribbon SBC
	
	.PARAMETER uxusername
	Enter here the REST Username. This is not the same username you use to login via the GUI
	
	.PARAMETER uxpassword
	Enter here the REST Password. This is not the same username you use to login via the GUI
	
	.EXAMPLE
	connect-uxgateway -uxhostname 1.1.1.1 -uxusername restuser -uxpassword Password01
	
	.EXAMPLE
	connect-uxgateway -uxhostname lyncsbc01.allthingsuc.co.uk -uxusername user1 -uxpassword Password02
	
	#>
	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0)]
     	[string]$uxhostname,
		[Parameter(Mandatory=$true,Position=1)]
		[string]$uxusername,
		[Parameter(Mandatory=$true,Position=2)]
		[string]$uxpassword
	)
	
	#Force TLS1.2
    	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12		


	#Login to SBC Edge
	$args1 = "Username=$uxusername&Password=$uxpassword"
	$url = "https://$uxhostname/rest/login"
	
	Try {
		$uxcommand1output = Invoke-RestMethod -Uri $url -Method Post -Body $args1 -SessionVariable global:sessionvar -ErrorAction Stop
	}
	Catch {
		throw "$uxhostname - Unable to connect to $uxhostname. Verify $uxhostname is accessible on the network. The error message returned is $_"
	}
	
	$global:uxhostname = $uxhostname

	#Check if the Login was successfull.HTTP code 200 is returned if login is successful
	If ( $uxcommand1output | select-string "<http_code>200</http_code>"){
		Write-verbose $uxcommand1output
	}
	Else {
		#Unable to Login
		throw "$uxhostname - Login unsuccessful, logon credentials are incorrect OR you may not be using REST Credentials.`
		For further information check `"http://www.allthingsuc.co.uk/accessing-sonus-ux-with-rest-apis`""
	}
}

#Function to grab SBC Edge system information
Function global:get-uxsysteminfo {
	<#
	.SYNOPSIS      
	 This cmdlet collects System information from Ribbon SBC.
	
	.EXAMPLE
	get-uxsysteminfo
	
	#>
	
	[cmdletbinding()]
	Param()
	$args1 = ""
	$url = "https://$uxhostname/rest/system"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method GET -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity)."
	}
	
		#Check if connection was successful.HTTP code 200 is returned
		If ( $uxrawdata | select-string "<http_code>200</http_code>"){
		 
		 	Write-Verbose $uxrawdata
		
			#Sanitise data and return as object
			Try {
				$m = $uxrawdata.IndexOf("<system href=")
				$length = ($uxrawdata.length - $m - 8)
				[xml]$uxdataxml =  $uxrawdata.substring($m,$length)
			}
			Catch {
				throw "Unable to convert received data into XML correctly. The error message is $_"
			}
			
		}
		Else {
			#Unable to Login
			throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
		}
		$uxdataxml.system
}

#Function to grab UX Global Call counters
Function global:get-uxsystemcallstats {
	<#
	.SYNOPSIS      
	 This cmdlet reports Call statistics from Ribbon SBC.
	 
	.DESCRIPTION
	 This cmdlet report Call statistics (global level only) from Ribbon SBC eg: Calls failed, Calls Succeeded, Call Currently Up, etc.
	
	.EXAMPLE
	get-uxsystemcallstats
	
	#>
	[cmdletbinding()]
	Param()
	$args1 = ""
	$url = "https://$uxhostname/rest/systemcallstats"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method GET -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
		#Check if connection was successful.HTTP code 200 is returned
		If ( $uxrawdata | select-string "<http_code>200</http_code>"){
		
			Write-Verbose $uxrawdata
			
			#Sanitise data and return as object
			Try {
				$m = $uxrawdata.IndexOf("<systemcallstats href=")
				$length = ($uxrawdata.length - $m - 8)
				[xml]$uxdataxml =  $uxrawdata.substring($m,$length)
			}
			Catch {
				throw "Unable to convert received data into XML correctly. The error message is $_"
			}
			
		}
		Else {
			#Unable to Login
			throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
		}
		$uxdataxml.systemcallstats
}

#Function to backup UX. When the backup succeeds there is no acknowledgement from UX.Best way to verify backup was successful is to check the backup file size
Function global:invoke-uxbackup {
	<#
	.SYNOPSIS      
	 This cmdlet performs backup of Ribbon SBC
	 
	.DESCRIPTION
	This cmdlet performs backup of Ribbon SBC.
	Ensure to check the size of the backup file to verify the backup was successful as Ribbon does not acknowledge this.If a backup file is 1KB it means the backup was unsuccessful.
	
	.PARAMETER backupdestination
	Enter here the backup folder where the backup file will be copied. Ensure you have got write permissions on this folder.
	
	.PARAMETER backupfilename
	Enter here the Backup file name. The backup file will automatically be appended with .tar.gz extension.
	
	.EXAMPLE
	invoke-uxbackup -backupdestination c:\backup -backupfilename lyncgw01backup01
	
	#>
	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0)]
     	[string]$backupdestination,
		[Parameter(Mandatory=$true,Position=1)]
		[string]$backupfilename
	)
	
	#Verify the backup location exists
	If (Test-Path $backupdestination) {}
	Else {
		throw "Backup destination inaccessible. Please ensure backup destination exists and you have write permissions to it"
	}
	
	$args1 = ""
	$url = "https://$uxhostname/rest/system?action=backup"
	
	Try {
		Invoke-RestMethod -Uri $url -Method POST -Body $args1 -WebSession $sessionvar -OutFile $backupdestination\$backupfilename.tar.gz -ErrorAction Stop
	}
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
}

#Function to return any resource (using GET)
Function global:get-uxresource {
	<#
	.SYNOPSIS      
	 This cmdlet makes a GET request to any valid UX resource. For full list of valid resources refer to https://support.sonus.net/display/UXAPIDOC
	 
	.DESCRIPTION      
	 This cmdlet makes a GET request to any valid UX resource. For full list of valid resources refer to https://support.sonus.net/display/UXAPIDOC.
	 The cmdlet is one of the most powerful as you can query pretty much any UX resource which supports GET requests!
	 
	.PARAMETER resource
	Enter a valid resource name here. For valid resource names refer to https://support.sonus.net/display/UXAPIDOC

	.EXAMPLE
	This example queries a "timing" resource 
	
	get-uxresource -resource timing

	.EXAMPLE
	This example queries a "certificate" resource 
	
	get-uxresource -resource certificate

	After you know the certificate id URL using the above cmdlet, you can perform second query to find more details:

	get-uxresource -resource certificate/1
	
	.LINK
	To find all the resources which can be queried, please refer to https://support.sonus.net/display/UXAPIDOC
	
	#>

	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0)]
		[string]$resource
	)
	
	$args1 = ""
	$url = "https://$uxhostname/rest/$resource"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method GET -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
		#Check if connection was successful.HTTP code 200 is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose $uxrawdata
		
		#Sanitise data and return as object
		Try {
			#Find any </status> and any whitespace following it
			$regex = [regex]'</status>\s+'

			write-verbose $regex.matches($uxrawdata)

			#Find the index of the point where </status> and whitespace following it ends.
			#To find this add the Index and length properties of the regex object
			$strstart = $regex.Match($uxrawdata).index+$regex.Match($uxrawdata).length

			#Now find </root> and any whitespace preceding it.
			$regex1 = [regex]'\s+</root>'
			$strend = $regex1.Match($uxrawdata).index
			
			#Fully formatted XML object
			[xml]$uxdataformatted = $uxrawdata.substring($strstart,$strend - $strstart)
		}
		Catch {
			throw "Unable to convert received data into XML correctly. The error message is $_.`nDisplaying rawxml $uxrawdata" 
		}
		
	}
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	#Return fully formatted XML object
	$uxdataformatted
}	

#Function to create a new resource on UX
Function global:new-uxresource {
	<#
	.SYNOPSIS      
	 This cmdlet initiates a PUT request to create a new UX resource. For full list of valid resources refer to https://support.sonus.net/display/UXAPIDOC
	 
	.DESCRIPTION      
	 This cmdlet  initiates a a PUT request to create a new UX resource. For full list of valid resources refer to https://support.sonus.net/display/UXAPIDOC.
	 Using this cmdlet you can create any resource on UX which supports PUT request!
	 
	.PARAMETER resource
	Enter a valid resource name here. For valid resource names refer to https://support.sonus.net/display/UXAPIDOC

	.EXAMPLE
	This example creates a new "sipservertable" resource 
	
	Grab the SIP Server table resource and next free available id
	((get-uxresource -resource sipservertable).sipservertable_list).sipservertable_pk
	
	Create new SIP server table and specify a free resource ID (15 here)
	new-uxresource -args "Description=LyncMedServers" -resource sipservertable/15
	
	.LINK
	To find all the resources which can be queried, please refer to https://support.sonus.net/display/UXAPIDOC
	
	#>

	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0)]
		[AllowEmptyString()]
		[string]$args,
		
		[Parameter(Mandatory=$true,Position=1)]
		[string]$resource
	)
	
	#Create the URL which will be passed to UX
	$url = "https://$uxhostname/rest/$resource"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method PUT -Body $args -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
		#Check if connection was successful.HTTP code 200 is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose $uxrawdata
		
		#Sanitise data and return as object
		Try {
			#Find any </status> and any whitespace following it
			$regex = [regex]'</status>\s+'

			write-verbose $regex.matches($uxrawdata)

			#Find the index of the point where </status> and whitespace following it ends.
			#To find this add the Index and length properties of the regex object
			$strstart = $regex.Match($uxrawdata).index+$regex.Match($uxrawdata).length

			#Now find </root> and any whitespace preceding it.
			$regex1 = [regex]'\s+</root>'
			$strend = $regex1.Match($uxrawdata).index
			
			#Fully formatted XML object
			[xml]$uxdataformatted = $uxrawdata.substring($strstart,$strend - $strstart)
		}
		Catch {
			throw "Unable to convert received data into XML correctly. The error message is $_.`nDisplaying rawxml $uxrawdata" 
		}
		
	}
	
	#If 500 message is returned
	ElseIf ($uxrawdata | select-string "<http_code>500</http_code>"){
		Write-Verbose -Message $uxrawdata
		throw "Unable to create a new resource. Ensure you have entered a unique resource id.Verify this using `"get-uxresource`" cmdlet"
	}
	
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	#Return fully formatted XML object
	write-verbose $uxdataformatted
}	

#Function to delete a resource on UX. 200OK is returned when a resource is deleted successfully. 500 if resource did not exist or couldn't delete it
Function global:remove-uxresource {
	<#
	.SYNOPSIS      
	 This cmdlet initates a DELETE request to remove a UX resource. For full list of valid resources refer to https://support.sonus.net/display/UXAPIDOC
	 
	.DESCRIPTION      
	 This cmdlet  initates a DELETE request to remove a UX resource. For full list of valid resources refer to https://support.sonus.net/display/UXAPIDOC.
	 You can delete any resource which supports DELETE request.
	 
	.PARAMETER resource
	Enter a valid resource name here. For valid resource names refer to https://support.sonus.net/display/UXAPIDOC

	.EXAMPLE
	Extract the transformation table id of the table you want to delete
	get-uxtransformationtable
	
	Now execute remove-uxresource cmdlet to delete the transformation table
	remove-uxresource -resource transformationtable/13
	
	.EXAMPLE
	 Extract the SIP Server table resource and find the id of the table you want to delete
	((get-uxresource -resource sipservertable).sipservertable_list).sipservertable_pk
	
	Now execute remove-uxresource cmdlet
	remove-uxresource -resource sipservertable/10
	
	.LINK
	To find all the resources which can be queried, please refer to https://support.sonus.net/display/UXAPIDOC
	
	#>

	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$false,Position=0)]
		[AllowEmptyString()]
		[string]$args,
		
		[Parameter(Mandatory=$true,Position=1)]
		[string]$resource
	)
	
	#The URL  which will be passed to the UX
	$url = "https://$uxhostname/rest/$resource"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method DELETE -Body $args -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
		#Check if connection was successful.HTTP code 200 is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose $uxrawdata
	}
	
	#If 500 message is returned
	ElseIf ($uxrawdata | select-string "<http_code>500</http_code>"){
		Write-Verbose -Message $uxrawdata
		throw "Unable to delete the resource. Verify using `"get-uxresource`" cmdlet, the resource does exist before deleting"
	}
	
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}

}	

#Function to create a modify and existing resource on the UX
Function global:set-uxresource {
	<#
	.SYNOPSIS      
	 This cmdlet initates a POST request to modify existing UX resource. For full list of valid resources refer to https://support.sonus.net/display/UXAPIDOC
	 
	.DESCRIPTION      
	 This cmdlet initates a POST request to modify existing UX resource. For full list of valid resources refer to https://support.sonus.net/display/UXAPIDOC.
	 
	.PARAMETER resource
	Enter a valid resource name here. For valid resource names refer to https://support.sonus.net/display/UXAPIDOC

	.EXAMPLE
	Assume you want to change the description of one of the SIPServer table.
	Using Get find the ID of the sip server table
	((get-uxresource -resource sipservertable).sipservertable_list).sipservertable_pk
	
	Once you have found the ID, issue the cmdlet below to modify the description
	set-uxresource -args Description=SBA2 -resource sipservertable/20
	
	.EXAMPLE
	Assume you want to change Description of the transformation table.
	Extract the transformation table id of the table you want to modify
	get-uxtransformationtable
	
	Once you have found the ID, issue the cmdlet below to modify the description
	set-uxresource -args "Description=Test5" -resource "transformationtable/12"
	
	.LINK
	To find all the resources which can be queried, please refer to https://support.sonus.net/display/UXAPIDOC
	
	#>

	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0)]
		[AllowEmptyString()]
		[string]$args,
		
		[Parameter(Mandatory=$true,Position=1)]
		[string]$resource
	)
	
	#Create the URL which will be passed to UX
	$url = "https://$uxhostname/rest/$resource"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method POST -Body $args -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
		#Check if connection was successful.HTTP code 200 is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose $uxrawdata
		
		#Sanitise data and return as object
		Try {
			#Find any </status> and any whitespace following it
			$regex = [regex]'</status>\s+'

			write-verbose $regex.matches($uxrawdata)

			#Find the index of the point where </status> and whitespace following it ends.
			#To find this add the Index and length properties of the regex object
			$strstart = $regex.Match($uxrawdata).index+$regex.Match($uxrawdata).length

			#Now find </root> and any whitespace preceding it.
			$regex1 = [regex]'\s+</root>'
			$strend = $regex1.Match($uxrawdata).index
			
			#Fully formatted XML object
			[xml]$uxdataformatted = $uxrawdata.substring($strstart,$strend - $strstart)
		}
		Catch {
			throw "Unable to convert received data into XML correctly. The error message is $_.`nDisplaying rawxml $uxrawdata" 
		}
		
	}
	
	#If 500 message is returned
	ElseIf ($uxrawdata | select-string "<http_code>500</http_code>"){
		Write-Verbose -Message $uxrawdata
		throw "Unable to modify the resource. Ensure the resource exists. You can verify this using `"get-uxresource`""
	}
	
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	#Return fully formatted XML object
	write-verbose $uxdataformatted
}	

#Function to get transformation table
Function global:get-uxtransformationtable {
	<#
	.SYNOPSIS      
	 This cmdlet displays all the transformation table names and ID's
	
	.EXAMPLE
	 get-uxtransformationtable
	
	#>

	[cmdletbinding()]
	Param()
	$args1 = ""
	$url = "https://$uxhostname/rest/transformationtable"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method GET -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Check if connection was successful.HTTP code 200 is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose $uxrawdata
		
		#Sanitise data and return as object
		Try {
			$m = $uxrawdata.IndexOf("<transformationtable_list")
			$length = ($uxrawdata.length - $m - 8)
			[xml]$uxdataxml =  $uxrawdata.substring($m,$length)
		}
		Catch {
			throw "Unable to convert received data into XML correctly. The error message is $_"
		}
		
	}
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Create template object to hold the values of Tranformation tables
	$objTemplate = New-Object psobject
	$objTemplate | Add-Member -MemberType NoteProperty -Name id -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Description -Value $null
	
	#Create an empty array which will contain the output
	$objResult = @()
		
	#This object contains all the Transformation table objects. Do a foreach to grab friendly names of the transformation tables
	foreach ($objtranstable in $uxdataxml.transformationtable_list.transformationtable_pk) {
		Try {
		$uxrawdata2 = Invoke-RestMethod -Uri $($objtranstable.href) -Method GET -WebSession $sessionvar -ErrorAction Stop
		}
	
		Catch {
			throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
		}
	
		#Check if connection was successful.HTTP code 200 is returned
		If ( $uxrawdata2 | select-string "<http_code>200</http_code>"){
	
			Write-Verbose $uxrawdata2
		
			#Sanitise data and return as object
			Try {
				$m = $uxrawdata2.IndexOf("<transformationtable id=")
				$length = ($uxrawdata2.length - $m - 8)
				[xml]$uxdataxml2 =  $uxrawdata2.substring($m,$length)
				
				#Create template object and stuff all the transformation tables into it
				$objTemp = $objTemplate | Select-Object *
				$objTemp.id = $uxdataxml2.transformationtable.id
				$objTemp.description = $uxdataxml2.transformationtable.description
				$objResult+=$objTemp
			}
			Catch {
				throw "Unable to convert received data into XML correctly. The error message is $_"
			}
			
		}
		Else {
			#Unable to Login
			throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
		}
	
	}
	#This object contains all the transformation tables with id to description mapping
	$objResult
}


#Function to get transformation table entries from a specified transformation table
Function global:get-uxtransformationentry {
	<#
	.SYNOPSIS      
	 This cmdlet displays the transformation table entries of a specified transformation table.
	 
	.DESCRIPTION
	This cmdlet displays the transformation table entries if a transformation table id is specified. To extract the tranformation table id execute "get-uxtransformationtable" cmdlet
	The output of the cmdlet contains InputField/OutputFields which are displayed as integer. To map the numbers to friendly names refer: bit.ly/Iy7JQS
	
	.PARAMETER uxtransformationtableid
	Enter here the transformation table id of the transformation table.To extract the tranformation table id execute "get-uxtransformationtable" cmdlet
	
	.EXAMPLE
	 get-uxtransformationentry -uxtransformationtableid 4
	
	#>
	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0,HelpMessage='To find the ID of the transformation table execute "get-uxtransformationtable" cmdlet')]
	    [int]$uxtransformationtableid
	)
	$args1 = ""
	#URL to grab the Transformation tables entry URL's when tranformation table ID is specified
	$url = "https://$uxhostname/rest/transformationtable/$uxtransformationtableid/transformationentry"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method GET -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Check if connection was successful.HTTP code 200 is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose -Message $uxrawdata
		
		#Sanitise data and return as object
		Try {
			$m = $uxrawdata.IndexOf("<transformationentry_list")
			$length = ($uxrawdata.length - $m - 8)
			[xml]$uxdataxml =  $uxrawdata.substring($m,$length)
		}
		Catch {
			throw "Unable to convert received data into XML correctly. The error message is $_"
		}
		
	}
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Grab the sequence of transformation entries in transformation.This information is stored in transformation table, so do have to query transformation table
	#FUNCTION get-uxresource IS USED IN THIS CMDLET
	Try {
		$transformationsequence = (((get-uxresource "transformationtable/$uxtransformationtableid").transformationtable).sequence).split(",")
	}
	
	Catch {
		throw "Unable to find the sequence of transformation entries.The error is $_"
	}
	
	#Create template object to hold the values of Tranformation tables
	$objTemplate = New-Object psobject
	$objTemplate | Add-Member -MemberType NoteProperty -Name InputField -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name InputFieldValue -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name OutputField -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name OutputFieldValue -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name MatchType -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Description -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ID -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name SequenceID -Value $null
	
	#Create an empty array which will contain the output
	$objResult = @()
		
	#This object contains all the Transformation table objects. Do a foreach to grab friendly names of the transformation tables
	foreach ($objtransentry in $uxdataxml.transformationentry_list.transformationentry_pk) {
		Try {
		$uxrawdata2 = Invoke-RestMethod -Uri $($objtransentry.href) -Method GET -WebSession $sessionvar -ErrorAction Stop
		}
	
		Catch {
			throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
		}
	
		#Check if connection was successful.HTTP code 200 is returned
		If ( $uxrawdata2 | select-string "<http_code>200</http_code>"){
	
			Write-Verbose $uxrawdata2
		
			#Sanitise data and return as object
			Try {
				$m = $uxrawdata2.IndexOf("<transformationentry id=")
				$length = ($uxrawdata2.length - $m - 8)
				[xml]$uxdataxml2 =  $uxrawdata2.substring($m,$length)
				
				#Sanitise the transformation table entry as it also contains the transformation table id (eg: 3:1, we only need 1)
				$transformationtableentryidraw = $uxdataxml2.transformationentry.id
				$transformationtableentryidfor = $transformationtableentryidraw.Substring(($transformationtableentryidraw.IndexOf(":")+1),$transformationtableentryidraw.Length-($transformationtableentryidraw.IndexOf(":")+1))
				
				#Create template object and stuff all the transformation tables into it
				$objTemp = $objTemplate | Select-Object *
				$objTemp.InputField = $uxdataxml2.transformationentry.InputField
				$objTemp.InputFieldValue = $uxdataxml2.transformationentry.InputFieldValue
				$objTemp.OutputField = $uxdataxml2.transformationentry.OutputField
				$objTemp.OutputFieldValue= $uxdataxml2.transformationentry.OutputFieldValue
				$objTemp.MatchType = $uxdataxml2.transformationentry.MatchType
				$objTemp.Description = $uxdataxml2.transformationentry.Description
				$objTemp.ID = $transformationtableentryidfor
				#Searches for the position in an array of a particular ID
				$objTemp.SequenceID = ($transformationsequence.IndexOf($objTemp.ID)+1)
				$objResult+=$objTemp
			}
			Catch {
				throw "Unable to convert received data into XML correctly. The error message is $_"
			}
			
		}
		Else {
			#Unable to Login
			throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
		}
	
	}
	#This object contains all the transformation tables with id to description mapping
	$objResult
}

#Function to create new transformation table
Function global:new-uxtransformationtable {
	<#
	.SYNOPSIS      
	 This cmdlet creates a new transformation table (not transformation table entry)
	 
	.DESCRIPTION
	This cmdlet creates a transformation table (not transformation table entry).
	
	.PARAMETER Description
	Enter here the Description (Name) of the Transformation table.This is what will be displayed in the Ribbon GUI
	
	.EXAMPLE
	 new-uxtransformationtable -Description "LyncToPBX"
	
	#>
	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0)]
		[ValidateLength(1,64)]
		[string]$Description
	)
	
	#DEPENDENCY ON get-uxtransformationtable FUNCTION TO GET THE NEXT AVAILABLE TRANSFORMATIONTABLEID
	Try {
		$transformationtableid = ((get-uxtransformationtable | select -ExpandProperty id | Measure-Object -Maximum).Maximum)+1
	}
	Catch {
		throw "Command failed when trying to execute the Transformationtableid using `"get-uxtransformationtable`" cmdlet.The error is $_"
	}
	
	#URL for the new transformation table
	$url = "https://$uxhostname/rest/transformationtable/$transformationtableid"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method PUT -Body "Description=$Description" -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	#If table is successfully created, 200OK is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose -Message $uxrawdata
	}
	#If 500 message is returned
	ElseIf ($uxrawdata | select-string "<http_code>500</http_code>"){
		Write-Verbose -Message $uxrawdata
		throw "Unable to create transformation table. Ensure you have entered a unique transformation table id"
	}
	#If no 200 or 500 message
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Sanitise data and return as object for verbose only
	Try {
		$m = $uxrawdata.IndexOf("<transformationtable id=")
		$length = ($uxrawdata.length - $m - 8)
		[xml]$uxdataxml =  $uxrawdata.substring($m,$length)
	}
	Catch {
		throw "Unable to convert received data into XML correctly. The error message is $_"
	}
	#Return Transformation table object just created
	write-verbose $uxdataxml.transformationtable
}

#Function to create new transformation table entry
Function global:new-uxtransformationentry {
	<#
	.SYNOPSIS      
	 This cmdlet creates transformation entries in existing transformation table
	 
	.DESCRIPTION
	This cmdlet creates transformation entries in existing transformation table.You need to specify the transformation table where these transformation entries should be created.
	
	.PARAMETER TransformationTableId
	Enter here the TransformationTableID of the transformation table where you want to add the transformation entry. This can be extracted using "get-uxtransformationtable" cmdlet
	
	.PARAMETER InputFieldType
	Enter here the code (integer) of the Field you want to add, eg:If you want to add "CalledNumber" add 0. Full information on which codes maps to which field please refer http://bit.ly/Iy7JQS

	.PARAMETER InputFieldValue
	Enter the value which should be matched.eg: If you want to match all the numbers between 2400 - 2659 you would enter here "^(2([45]\d{2}|6[0-5]\d))$"

	.PARAMETER OutputFieldType
	Enter here the code (integer) of the Field you want to add, eg:If you want to add "CalledNumber" add 0. Full information on which codes maps to which field please refer http://bit.ly/Iy7JQS

	.PARAMETER OutputFieldValue
	Enter here the output of the Input value.eg: If you want to change input of "^(2([45]\d{2}|6[0-5]\d))$" to +44123456XXXX, you would enter here +44123456\1

	.PARAMETER Description
	Enter here the Description (Name) of the Transformation entry. This is what will be displayed in the Ribbon GUI

	.PARAMETER MatchType
	Enter here if the Transformation entry you will create will be Mandatory(0) or Optional(1). If this parameter is not specified the transformation table will be created as Optional

	.EXAMPLE
	Assume you want to create a new transformation table.
	First determine the ID of the transformation table in which you want to create the new transformation entry.
	
	get-uxtransformationtable

	This example creates an Optional (default) transformation entry converting Called Number range  2400 - 2659  to Called Number +44123456XXXX
	
	new-uxtransformationentry -TransformationTableId 6 -InputFieldType 0 -InputFieldValue '^(2([45]\d{2}|6[0-5]\d))$' -OutputFieldType 0 -OutputFieldValue '+44123456\1' -Description "ExtToDDI"
	
	.EXAMPLE
	This example creates an Optional transformation entry converting Calling Number beginning with 0044xxxxxx to Calling Number +44xxxxxx
	
	new-uxtransformationentry -TransformationTableId 3 -InputFieldType 3 -InputFieldValue '00(44\d(.*))' -OutputFieldType 3 -OutputFieldValue '+\1' -Description "UKCLIToE164"
	
	.EXAMPLE
	This example creates a Mandatory CLI (Calling Number)passthrough
	
	new-uxtransformationentry -TransformationTableId 9 -InputFieldType 3 -InputFieldValue '(.*)' -OutputFieldType 3 -OutputFieldValue '\1' -Description "PassthroughCLI" -MatchType 0
	
	.LINK
	For Input/Output Field Value Code mappings, please refer to http://bit.ly/Iy7JQS
	
	#>
	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0)]
		[int]$TransformationTableId,
		
		[Parameter(Mandatory=$true,Position=1,HelpMessage="Refer http://bit.ly/Iy7JQS for further detail")]
		[ValidateRange(0,31)]
		[int]$InputFieldType,
		
		[Parameter(Mandatory=$true,Position=2)]
		[ValidateLength(1,256)]
		[string]$InputFieldValue,
		
		[Parameter(Mandatory=$true,Position=3,HelpMessage="Refer http://bit.ly/Iy7JQS for for further detail")]
		[ValidateRange(0,31)]
		[string]$OutputFieldType,
		
		[Parameter(Mandatory=$true,Position=4)]
		[ValidateLength(1,256)]
		[string]$OutputFieldValue,
		
		[Parameter(Mandatory=$false,Position=6)]
		[ValidateLength(1,64)]
		[string]$Description,
		
		[Parameter(Mandatory=$False,Position=5)]
		[ValidateSet(0,1)]
		[int]$MatchType = 1
		
	)
	
	#DEPENDENCY ON get-uxtransformationentry FUNCTION TO GET THE NEXT AVAILABLE TRANSFORMATIONTABLEID
	Try {
		$transtableentryid = ((get-uxtransformationentry -uxtransformationtableid $TransformationTableId | select -ExpandProperty id | Measure-Object -Maximum).Maximum)+1
	}
	Catch {
		throw "Command failed when trying to execute the Transformationtableentryid using `"get-uxtransformationentry`" cmdlet.The error is $_"
	}
	
	#URL for the new transformation table
	$url = "https://$uxhostname/rest/transformationtable/$TransformationTableId/transformationentry/$transtableentryid"
	#Replace "+" with "%2B" as + is considered a Space in HTTP/S world, so gets processed as space when used in a command
	$InputFieldValue = $InputFieldValue.replace("+",'%2B')
	$OutputFieldValue = $OutputFieldValue.replace("+",'%2B')
	#Variable which contains all the information we require to create a transformation table.
	$args2 = "Description=$Description&InputField=$InputFieldType&InputFieldValue=$InputFieldValue&OutputField=$OutputFieldType&OutputFieldValue=$OutputFieldValue&MatchType=$MatchType"
	
	Try {
		$uxrawdata3 = Invoke-RestMethod -Uri $url -Method PUT -body $args2 -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	#If table is successfully created, 200OK is returned
	If ( $uxrawdata3 | select-string "<http_code>200</http_code>"){
	
		Write-Verbose -Message $uxrawdata3
	}
	#If 500 message is returned
	ElseIf ($uxrawdata3 | select-string "<http_code>500</http_code>"){
		Write-Verbose -Message $uxrawdata3
		throw "Unable to create transformation table. Ensure you have entered a unique transformation table id"
	}
	#If no 200 or 500 message
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Sanitise data and return as object for verbose only
	Try {
		$m1 = $uxrawdata3.IndexOf("<transformationentry id=")
		$length1 = ($uxrawdata3.length - $m1 - 8)
		[xml]$uxdataxml3 =  $uxrawdata3.substring($m1,$length1)
	}
	Catch {
		throw "Unable to convert received data into XML correctly. The error message is $_"
	}
	
	#Return Transformation table object just created for verbose only
	write-verbose $uxdataxml3.transformationentry
	
}

#Function to get sipserver table
Function global:get-uxsipservertable {
	<#
	.SYNOPSIS      
	 This cmdlet displays all the sipserver table names and ID's
	
	.EXAMPLE
	 get-uxsipservertable
	
	#>

	[cmdletbinding()]
	Param()
	$args1 = ""
	$url = "https://$uxhostname/rest/sipservertable"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method GET -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Check if connection was successful.HTTP code 200 is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose $uxrawdata
		
		#Sanitise data and return as object
		Try {
			$m = $uxrawdata.IndexOf("<sipservertable_list")
			$length = ($uxrawdata.length - $m - 8)
			[xml]$uxdataxml =  $uxrawdata.substring($m,$length)
		}
		Catch {
			throw "Unable to convert received data into XML correctly. The error message is $_"
		}
		
	}
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Create template object to hold the values of Tranformation tables
	$objTemplate = New-Object psobject
	$objTemplate | Add-Member -MemberType NoteProperty -Name id -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Description -Value $null
	
	#Create an empty array which will contain the output
	$objResult = @()
		
	#This object contains all the sipserver table objects. Do a foreach to grab friendly names of the sipserver tables
	foreach ($objtranstable in $uxdataxml.sipservertable_list.sipservertable_pk) {
		Try {
		$uxrawdata2 = Invoke-RestMethod -Uri $($objtranstable.href) -Method GET -WebSession $sessionvar -ErrorAction Stop
		}
	
		Catch {
			throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
		}
	
		#Check if connection was successful.HTTP code 200 is returned
		If ( $uxrawdata2 | select-string "<http_code>200</http_code>"){
	
			Write-Verbose $uxrawdata2
		
			#Sanitise data and return as object
			Try {
				$m = $uxrawdata2.IndexOf("<sipservertable id=")
				$length = ($uxrawdata2.length - $m - 8)
				[xml]$uxdataxml2 =  $uxrawdata2.substring($m,$length)
				
				#Create template object and stuff all the sipserver tables into it
				$objTemp = $objTemplate | Select-Object *
				$objTemp.id = $uxdataxml2.sipservertable.id
				$objTemp.description = $uxdataxml2.sipservertable.description
				$objResult+=$objTemp
			}
			Catch {
				throw "Unable to convert received data into XML correctly. The error message is $_"
			}
			
		}
		Else {
			#Unable to Login
			throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
		}
	
	}
	#This object contains all the sipserver tables with id to description mapping
	$objResult
}

#Function to create new sipserver table
Function global:new-uxsipservertable {
	<#
	.SYNOPSIS      
	 This cmdlet creates a new sipserver table (not sipserver table entry)
	 
	.DESCRIPTION
	This cmdlet creates a sipserver table (not sipserver table entry).
	
	.PARAMETER Description
	Enter here the Description (Name) of the sipserver table.This is what will be displayed in the Ribbon GUI
	
	.EXAMPLE
	 new-uxsipservertable -Description "LyncToPBX"
	
	#>
	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0)]
		[ValidateLength(1,64)]
		[string]$Description
	)
	
	#DEPENDENCY ON get-uxsipservertable FUNCTION TO GET THE NEXT AVAILABLE SIPSERVER TABLEID
	Try {
		$sipservertableid = ((get-uxsipservertableentry | select -ExpandProperty id | Measure-Object -Maximum).Maximum)+1
	}
	Catch {
		throw "Command failed when trying to execute the sipservertableid using `"get-uxsipservertable`" cmdlet.The error is $_"
	}
	
	#URL for the new sipserver table
	$url = "https://$uxhostname/rest/sipservertable/$sipservertableid"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method PUT -Body "Description=$Description" -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	#If table is successfully created, 200OK is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose -Message $uxrawdata
	}
	#If 500 message is returned
	ElseIf ($uxrawdata | select-string "<http_code>500</http_code>"){
		Write-Verbose -Message $uxrawdata
		throw "Unable to create sipserver table. Ensure you have entered a unique sipserver table id"
	}
	#If no 200 or 500 message
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Sanitise data and return as object for verbose only
	Try {
		$m = $uxrawdata.IndexOf("<sipservertable id=")
		$length = ($uxrawdata.length - $m - 8)
		[xml]$uxdataxml =  $uxrawdata.substring($m,$length)
	}
	Catch {
		throw "Unable to convert received data into XML correctly. The error message is $_"
	}
	#Return sipserver table object just created
	write-verbose $uxdataxml.sipservertable
}

#Function to create new sipserver entry
Function global:new-uxsipserverentry {
	<#
	.SYNOPSIS      
	 This cmdlet creates a new host/domain in existing sipserver table
	 
	.DESCRIPTION
	This cmdlet creates a new host in an existing sipserver table.You need to specify the sipserver table where these transformation entries should be created.
	
	.PARAMETER SipServerTableId
	Enter here the SIPServer ID of the sipserver table where you want to add a new host entry. This can be extracted using "get-uxsipservertable" cmdlet

	.PARAMETER ServerLookup
	Enter here the SIPServer ID of the sipserver table where you want to add a new host entry. This can be extracted using "get-uxsipservertable" cmdlet
	
	.PARAMETER Priority
	Enter here the code (integer) of the Field you want to add, eg:If you want to add "CalledNumber" add 0. Full information on which codes maps to which field please refer http://bit.ly/Iy7JQS

	.PARAMETER Host
	Enter the value which should be matched.eg: If you want to match all the numbers between 2400 - 2659 you would enter here "^(2([45]\d{2}|6[0-5]\d))$"

	.PARAMETER HostIpVersion
	Enter here the code (integer) of the Field you want to add, eg:If you want to add "CalledNumber" add 0. Full information on which codes maps to which field please refer http://bit.ly/Iy7JQS

	.PARAMETER Port
	Enter here the output of the Input value.eg: If you want to change input of "^(2([45]\d{2}|6[0-5]\d))$" to +44123456XXXX, you would enter here +44123456\1

	.PARAMETER Protocol
	Enter here the Description (Name) of the Transformation entry. This is what will be displayed in the Ribbon GUI

	.PARAMETER TLSProfile
	Enter here if the Transformation entry you will create will be Mandatory(0) or Optional(1). If this parameter is not specified the transformation table will be created as Optional

	.PARAMETER KeepAliveFrequency
	Enter here if the Transformation entry you will create will be Mandatory(0) or Optional(1). If this parameter is not specified the transformation table will be created as Optional

	.PARAMETER RecoverFrequency
	Enter here if the Transformation entry you will create will be Mandatory(0) or Optional(1). If this parameter is not specified the transformation table will be created as Optional

	.PARAMETER LocalUserName
	Enter here if the Transformation entry you will create will be Mandatory(0) or Optional(1). If this parameter is not specified the transformation table will be created as Optional

	.PARAMETER PeerUserName
	Enter here if the Transformation entry you will create will be Mandatory(0) or Optional(1). If this parameter is not specified the transformation table will be created as Optional

	.PARAMETER RemoteAuthorizationTable
	Enter here if the Transformation entry you will create will be Mandatory(0) or Optional(1). If this parameter is not specified the transformation table will be created as Optional

	.PARAMETER ContactRegistrantTable
	Enter here if the Transformation entry you will create will be Mandatory(0) or Optional(1). If this parameter is not specified the transformation table will be created as Optional

	.PARAMETER SessionURIValidation
	Enter here if the Transformation entry you will create will be Mandatory(0) or Optional(1). If this parameter is not specified the transformation table will be created as Optional

	.PARAMETER ReuseTransport
	Enter here if the Transformation entry you will create will be Mandatory(0) or Optional(1). If this parameter is not specified the transformation table will be created as Optional

	.PARAMETER TransportSocket
	Enter here if the Transformation entry you will create will be Mandatory(0) or Optional(1). If this parameter is not specified the transformation table will be created as Optional

	.PARAMETER ReuseTimeout
	Enter here if the Transformation entry you will create will be Mandatory(0) or Optional(1). If this parameter is not specified the transformation table will be created as Optional


	.EXAMPLE
	Assume you want to create a new transformation table.
	First determine the ID of the transformation table in which you want to create the new transformation entry.
	
	get-uxtransformationtable

	This example creates an Optional (default) transformation entry converting Called Number range  2400 - 2659  to Called Number +44123456XXXX
	
	new-uxtransformationentry -TransformationTableId 6 -InputFieldType 0 -InputFieldValue '^(2([45]\d{2}|6[0-5]\d))$' -OutputFieldType 0 -OutputFieldValue '+44123456\1' -Description "ExtToDDI"
	
	.EXAMPLE
	This example creates an Optional transformation entry converting Calling Number beginning with 0044xxxxxx to Calling Number +44xxxxxx
	
	new-uxtransformationentry -TransformationTableId 3 -InputFieldType 3 -InputFieldValue '00(44\d(.*))' -OutputFieldType 3 -OutputFieldValue '+\1' -Description "UKCLIToE164"
	
	.EXAMPLE
	This example creates a Mandatory CLI (Calling Number)passthrough
	
	new-uxtransformationentry -TransformationTableId 9 -InputFieldType 3 -InputFieldValue '(.*)' -OutputFieldType 3 -OutputFieldValue '\1' -Description "PassthroughCLI" -MatchType 0
	
	.LINK
	For Input/Output Field Value Code mappings, please refer to http://bit.ly/Iy7JQS
	
	#>
	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0)]
		[int]$SipServerTableId,

		[Parameter(Mandatory=$false,Position=1,HelpMessage="Specifies the protocol to use for sending SIP messages")]
		[ValidateSet(0,1)]
		[int]$ServerLookup = 0,
		
		[Parameter(Mandatory=$true,Position=0,HelpMessage="Specifies the priority of this server")]
		[ValidateRange(0,16)]
		[int]$Priority,

		[Parameter(Mandatory=$true,Position=1,HelpMessage="Specifies the IP address or FQDN where this Signaling Group sends SIP messages")]
		[ValidateLength(1,256)]
		[string]$Host,

		[Parameter(Mandatory=$false,Position=4,HelpMessage="Specifies IPv4 addresses or IPv6 addresses")]
		[int]$HostIpVersion = 0,

		[Parameter(Mandatory=$false,Position=5,HelpMessage="Specifies the port number to send SIP messages")]
		[ValidateRange(1024,65535)]
		[string]$Port = 5061,

		[Parameter(Mandatory=$false,Position=6,HelpMessage="Specifies the protocol to use for sending SIP messages")]
		[ValidateRange(0,9)]
		[string]$Protocol = 2,
		
		[Parameter(Mandatory=$false,Position=7,HelpMessage="Specifies the TLS Profile ID")]
		[ValidateRange(0,9)]
		[string]$TLSProfileid,
		
		[Parameter(Mandatory=$false,Position=8,HelpMessage="Specifies the method to monitor server. None(0), SIP Options(1)")]
		[ValidateSet(0,1)]
		[int]$Monitor = 1

<#		[Parameter(Mandatory=$false,Position=9)]
		[ValidateRange(0,2)]
		[int]$ServerType = 0,

		[Parameter(Mandatory=$false,Position=10)]
		[ValidateLenght(1,256)]
		[string]$DomainName,

		[Parameter(Mandatory=$false,Position=11)]
		[ValidateRange(0,65535)]
		[int]$Weight = 0
		
		Parameters to be added later if needed
		
		[Parameter(Mandatory=$false,Position=11)]
		[ValidateRange(30,300)]
		[string]$KeepAliveFrequency,
		
		[Parameter(Mandatory=$false,Position=12)]
		[ValidateRange(5,500)]
		[string]$RecoverFrequency,
		
		[Parameter(Mandatory=$false,Position=13)]
		[ValidateLength(1,256)]
		[string]$LocalUserName,
		
		[Parameter(Mandatory=$false,Position=14)]
		[ValidateLenght(1,256)]
		[string]$PeerUserName,
		
		[Parameter(Mandatory=$false,Position=15)]
		[ValidateRange(0,16)]
		[string]$RemoteAuthorizationTable,
		
		[Parameter(Mandatory=$false,Position=16)]
		[ValidateRange(0,16)]
		[string]$ContactRegistrantTable,
		
		[Parameter(Mandatory=$false,Position=17)]
		[ValidateSet(0,1)]
		[string]$SessionURIValidation,
		
		[Parameter(Mandatory=$false,Position=18)]
		[ValidateSet(0,1)]
		[string]$ReuseTransport,
		
		[Parameter(Mandatory=$false,Position=19)]
		[ValidateSet(1,4)]
		[string]$TransportSocket,
		
		[Parameter(Mandatory=$False,Position=20)]
		[ValidateSet(0,1)]
		[int]$ReuseTimeout
#>		
	)
	
	#DEPENDENCY ON get-uxtransformationentry FUNCTION TO GET THE NEXT AVAILABLE TRANSFORMATIONTABLEID
	Try {	
		$sipserverentryid = ((get-uxsipservertableentry -sipservertableid $SipServerTableId| measure-object ID -maximum |Select -ExpandProperty Maximum)+1)
	}
	Catch {
		throw "Command failed when trying to execute the Transformationtableentryid using `"get-uxsipserverentry`" cmdlet.The error is $_"
	}
	
	#URL for the new transformation table
	$url = "https://$uxhostname/rest/sipservertable/$SipServerTableId/sipserver/$sipserverentryid"
	
	#Replace "+" with "%2B" as + is considered a Space in HTTP/S world, so gets processed as space when used in a command
	#$InputFieldValue = $InputFieldValue.replace("+",'%2B')
	#$OutputFieldValue = $OutputFieldValue.replace("+",'%2B')
	#Variable which contains all the information we require to create a transformation table.

	#Adding standard values for required parameters.	
	$ServerType = 0
	$DomainName = ""
	$Weight = 0
	$args2 = "SipServerTableId=$SipServerTableId&ServerLookup=$ServerLookup&Priority=$Priority&Host=$Host&Port=$Port&Protocol=$Protocol&TLSProfileID=$TLSProfileid&Monitor=$Monitor&ServerType=$ServerType&DomainName=$DomainName&Weight=$Weight"
	
	Try {
		$uxrawdata3 = Invoke-RestMethod -Uri $url -Method PUT -body $args2 -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	#If table is successfully created, 200OK is returned
	If ( $uxrawdata3 | select-string "<http_code>200</http_code>"){
	
		Write-Verbose -Message $uxrawdata3
	}
	#If 500 message is returned
	ElseIf ($uxrawdata3 | select-string "<http_code>500</http_code>"){
		Write-Verbose -Message $uxrawdata3
		throw "Unable to create sipserver entry. Ensure you have entered a unique sipserver table id"
	}
	#If no 200 or 500 message
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Sanitise data and return as object for verbose only
	Try {
		$m1 = $uxrawdata3.IndexOf("<sipserver id=")
		$length1 = ($uxrawdata3.length - $m1 - 8)
		[xml]$uxdataxml3 =  $uxrawdata3.substring($m1,$length1)
	}
	Catch {
		throw "Unable to convert received data into XML correctly. The error message is $_"
	}
	#Return sipserver entry object just created for verbose only
	write-verbose $uxdataxml3.sipserver
	
}

#Function to get sipprofile
Function global:get-uxsipprofile {
	<#
	.SYNOPSIS      
	 This cmdlet displays all the sipprofile names and ID's
	
	.EXAMPLE
	 get-uxsipprofile
	
	#>

	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$false,Position=0)]
		[int]$sipprofileid

	)

# Check if sipserver table id was added as parameter
 if (-Not $sipprofileid) { 

	$args1 = ""
	$url = "https://$uxhostname/rest/sipprofile"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method GET -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Check if connection was successful.HTTP code 200 is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose $uxrawdata
		
		#Sanitise data and return as object
		Try {
			$m = $uxrawdata.IndexOf("<sipprofile_list")
			$length = ($uxrawdata.length - $m - 8)
			[xml]$uxdataxml =  $uxrawdata.substring($m,$length)
		}
		Catch {
			throw "Unable to convert received data into XML correctly. The error message is $_"
		}
		
	}
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Create template object to hold the values of Tranformation tables
	$objTemplate = New-Object psobject
	$objTemplate | Add-Member -MemberType NoteProperty -Name id -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Description -Value $null
	
	#Create an empty array which will contain the output
	$objResult = @()
		
	#This object contains all the sipprofile table objects. Do a foreach to grab friendly names of the sipprofile tables
	foreach ($objtranstable in $uxdataxml.sipprofile_list.sipprofile_pk) {
		Try {
		$uxrawdata2 = Invoke-RestMethod -Uri $($objtranstable.href) -Method GET -WebSession $sessionvar -ErrorAction Stop
		}
	
		Catch {
			throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
		}
	
		#Check if connection was successful.HTTP code 200 is returned
		If ( $uxrawdata2 | select-string "<http_code>200</http_code>"){
	
			Write-Verbose $uxrawdata2
		
			#Sanitise data and return as object
			Try {
				$m = $uxrawdata2.IndexOf("<sipprofile id=")
				$length = ($uxrawdata2.length - $m - 8)
				[xml]$uxdataxml2 =  $uxrawdata2.substring($m,$length)
				
				#Create template object and stuff all the sipprofile tables into it
				$objTemp = $objTemplate | Select-Object *
				$objTemp.id = $uxdataxml2.sipprofile.id
				$objTemp.description = $uxdataxml2.sipprofile.description
				$objResult+=$objTemp
			}
			Catch {
				throw "Unable to convert received data into XML correctly. The error message is $_"
			}
			
		}
		Else {
			#Unable to Login
			throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
		}
	
	}
	#This object contains all the sipprofile tables with id to description mapping
	$objResult
}

Else {get-uxsipprofileid $sipprofileid}

}

#Function to get sipserver table entries from a specified sipserver table
Function global:get-uxsipservertableentry {
	<#
	.SYNOPSIS      
	 This cmdlet displays the sipserver table entries of a specified sipserver table.
	 
	.DESCRIPTION
	This cmdlet displays the sipserver table entries if a sipserver table id is specified. To extract the sipserver table id execute "get-uxsipservertable" cmdlet
	The output of the cmdlet contains InputField/OutputFields which are displayed as integer. To map the numbers to friendly names refer: bit.ly/Iy7JQS
	
	.PARAMETER uxsipservertableid
	Enter here the sipserver table id of the sipserver table.To extract the sipserver table id execute "get-uxsipservertable" cmdlet
	
	.EXAMPLE
	 get-uxsipservertableentry -uxsipservertableid 4
	
	#>
	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0,HelpMessage='To find the ID of the sipserver table execute "get-uxsipservertable" cmdlet')]
	    [int]$sipservertableid
	)
	$args1 = ""
	#URL to grab the sipserver tables entry URL's when tranformation table ID is specified
	$url = "https://$uxhostname/rest/sipservertable/$sipservertableid/sipserver"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method GET -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Check if connection was successful.HTTP code 200 is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose -Message $uxrawdata
		
		#Sanitise data and return as object
		Try {
			$m = $uxrawdata.IndexOf("<sipserver_list")
			$length = ($uxrawdata.length - $m - 8)
			[xml]$uxdataxml =  $uxrawdata.substring($m,$length)
		}
		Catch {
			throw "Unable to convert received data into XML correctly. The error message is $_"
		}
		
	}
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	$m

	#Grab the sequence of sipserver entries in sipserver.This information is stored in sipserver table, so do have to query sipserver table
	#FUNCTION get-uxresource IS USED IN THIS CMDLET
	Try {
		$transformationsequence = (((get-uxresource "sipservertable/$sipservertableid").sipservertable).sequence).split(",")
	}
	
	Catch {
		throw "Unable to find the sequence of sipserver entries.The error is $_"
	}
	
	#Create template object to hold the values of Tranformation tables
	$objTemplate = New-Object psobject
	$objTemplate | Add-Member -MemberType NoteProperty -Name ID -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Host -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Port -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TLSProfileID -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name AuthorizationOnRefresh -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ClearRemoteRegistrationOnStartup -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ContactRegistrantTableID -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ContactURIRandomizer -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name DomainName -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name HostIpVersion -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name KeepAliveFrequency -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name LocalUserName -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Monitor -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name PeerUserName -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Priority -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Protocol -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RecoverFrequency -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RemoteAuthorizationTableID -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RetryNonStaleNonce -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ReuseTimeout -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ReuseTransport -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ServerLookup -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ServerType -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ServiceName -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name SessionURIValidation -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name StaggerRegistration -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TransportSocket -Value $null
 	$objTemplate | Add-Member -MemberType NoteProperty -Name Weight -Value $null



	
	#Create an empty array which will contain the output
	$objResult = @()
		
	#This object contains all the sipserver table objects. Do a foreach to grab friendly names of the sipserver tables
	foreach ($objtransentry in $uxdataxml.sipserver_list.sipserver_pk) {
		Try {
		$uxrawdata2 = Invoke-RestMethod -Uri $($objtransentry.href) -Method GET -WebSession $sessionvar -ErrorAction Stop
		}
	
		Catch {
			throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
		}

		#Check if connection was successful.HTTP code 200 is returned
		If ( $uxrawdata2 | select-string "<http_code>200</http_code>"){
	
			
		
			#Sanitise data and return as object
			Try {
				$m = $uxrawdata2.IndexOf("<sipserver id=")
				$length = ($uxrawdata2.length - $m - 8)
				[xml]$uxdataxml2 =  $uxrawdata2.substring($m,$length)
				
				#Sanitise the sipserver table entry as it also contains the sipserver table id (eg: 3:1, we only need 1)
				$sipservertableentryidraw = $uxdataxml2.sipserver.id
				$sipservertableentryidfor = $sipservertableentryidraw.Substring(($sipservertableentryidraw.IndexOf(":")+1),$sipservertableentryidraw.Length-($sipservertableentryidraw.IndexOf(":")+1))
				
				#Create template object and stuff all the sipserver tables into it
				$objTemp = $objTemplate | Select-Object *
				$objTemp.ID = $sipservertableentryidfor
				$objTemp.AuthorizationOnRefresh = $uxdataxml2.sipserver.AuthorizationOnRefresh
				$objTemp.ClearRemoteRegistrationOnStartup = $uxdataxml2.sipserver.ClearRemoteRegistrationOnStartup
				$objTemp.ContactRegistrantTableID = $uxdataxml2.sipserver.ContactRegistrantTableID
				$objTemp.ContactURIRandomizer= $uxdataxml2.sipserver.ContactURIRandomizer
				$objTemp.DomainName = $uxdataxml2.sipserver.DomainName
				$objTemp.Host = $uxdataxml2.sipserver.Host
				$objTemp.HostIpVersion = $uxdataxml2.sipserver.HostIpVersion
				$objTemp.KeepAliveFrequency = $uxdataxml2.sipserver.KeepAliveFrequency
				$objTemp.LocalUserName = $uxdataxml2.sipserver.LocalUserName
				$objTemp.Monitor = $uxdataxml2.sipserver.Monitor
				$objTemp.PeerUserName = $uxdataxml2.sipserver.PeerUserName
				$objTemp.Port = $uxdataxml2.sipserver.Port
				$objTemp.Priority = $uxdataxml2.sipserver.Priority
				$objTemp.Protocol = $uxdataxml2.sipserver.Protocol
				$objTemp.RecoverFrequency = $uxdataxml2.sipserver.RecoverFrequency
				$objTemp.RemoteAuthorizationTableID = $uxdataxml2.sipserver.RemoteAuthorizationTableID
				$objTemp.RetryNonStaleNonce = $uxdataxml2.sipserver.RetryNonStaleNonce
				$objTemp.ReuseTimeout = $uxdataxml2.sipserver.ReuseTimeout
				$objTemp.ReuseTransport = $uxdataxml2.sipserver.ReuseTransport
				$objTemp.ServerLookup = $uxdataxml2.sipserver.ServerLookup
				$objTemp.ServerType = $uxdataxml2.sipserver.ServerType
				$objTemp.ServiceName = $uxdataxml2.sipserver.ServiceName
				$objTemp.SessionURIValidation = $uxdataxml2.sipserver.SessionURIValidation
				$objTemp.StaggerRegistration= $uxdataxml2.sipserver.StaggerRegistration
				$objTemp.TLSProfileID = $uxdataxml2.sipserver.TLSProfileID
				$objTemp.TransportSocket = $uxdataxml2.sipserver.TransportSocket
				$objTemp.Weight = $uxdataxml2.sipserver.Weight
				

				#Searches for the position in an array of a particular ID
				$objResult+=$objTemp

				
			}
			Catch {
				throw "Unable to convert received data into XML correctly. The error message is $_"
			}
			
		}
		Else {
			#Unable to Login
			throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
		}
	
	}
	#This object contains all the sipserver tables with id to description mapping
	$objResult
}

#Function to get sipprofileid
Function global:get-uxsipprofileid {
	<#
	.SYNOPSIS      
	 This cmdlet displays all the sipprofile names and ID's
	
	.EXAMPLE
	 get-uxsipprofileid
	
	#>

	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0,HelpMessage='To find the ID of the transformation table execute "get-uxtransformationtable" cmdlet')]
	    	[int]$sipprofileid
	)
	$args1 = ""
	$url = "https://$uxhostname/rest/sipprofile/$sipprofileid"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method GET -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Check if connection was successful.HTTP code 200 is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose $uxrawdata
		
		#Sanitise data and return as object
		Try {
			$m = $uxrawdata.IndexOf("<sipprofile id=")
			$length = ($uxrawdata.length - $m - 8)
			[xml]$uxdataxml =  $uxrawdata.substring($m,$length)
		}
		Catch {
			throw "Unable to convert received data into XML correctly. The error message is $_"
		}
		
	}
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	

	#Create template object to hold the values of Tranformation tables
	$objTemplate = New-Object psobject
	$objTemplate | Add-Member -MemberType NoteProperty -Name Description -Value $null	
	$objTemplate | Add-Member -MemberType NoteProperty -Name AllowHeader -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name CgNumberNameFromHdr -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ConnectionInfoInMediaSection -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name DiagnosticsHeader -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name DigitPreference -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name DiversionSelection -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ElinIdentifier -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name FQDNinContactHeader -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name FQDNinFromHeader -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name MaxRetransmits -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Option100Rel -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name OptionPath -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name OptionTimer -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name OptionUpdate -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name OriginFieldUserName -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name PidfPlPassthru -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RecordRouteHdrPref -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RedundancyRetryTimer -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name SDPHandling -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name SendAssertHdrAlways -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name SendNumberofAudioChan -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name SessionName -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name SessionTimer -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name SessionTimerExp -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name SessionTimerMin -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name StaticHost -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TerminateOnRefreshFailure -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TimerC -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TimerD -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TimerJ -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TimerT1 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TimerT2 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TimerT4 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TransportTimeoutTimer -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TrustedInterface -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name UnknownPlPassthru -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name UserAgentHeader -Value $null

	
	#Create an empty array which will contain the output
	$objResult = @()

		
	#Create template object and stuff all the sipprofile values into it
				$objTemp = $objTemplate | Select-Object *
				$objTemp.Description = $uxdataxml.sipprofile.Description
				$objTemp.AllowHeader = $uxdataxml.sipprofile.AllowHeader
				$objTemp.CgNumberNameFromHdr = $uxdataxml.sipprofile.CgNumberNameFromHdr
				$objTemp.ConnectionInfoInMediaSection = $uxdataxml.sipprofile.ConnectionInfoInMediaSection
				$objTemp.DiagnosticsHeader = $uxdataxml.sipprofile.DiagnosticsHeader
				$objTemp.DigitPreference = $uxdataxml.sipprofile.DigitPreference
				$objTemp.DiversionSelection = $uxdataxml.sipprofile.DiversionSelection
				$objTemp.ElinIdentifier = $uxdataxml.sipprofile.ElinIdentifier
				$objTemp.FQDNinContactHeader = $uxdataxml.sipprofile.FQDNinContactHeader
				$objTemp.FQDNinFromHeader = $uxdataxml.sipprofile.FQDNinFromHeader
				$objTemp.MaxRetransmits = $uxdataxml.sipprofile.MaxRetransmits
				$objTemp.Option100Rel = $uxdataxml.sipprofile.Option100Rel
				$objTemp.OptionPath = $uxdataxml.sipprofile.OptionPath
				$objTemp.OptionUpdate = $uxdataxml.sipprofile.OptionUpdate
				$objTemp.OriginFieldUserName = $uxdataxml.sipprofile.OriginFieldUserName
				$objTemp.PidfPlPassthru = $uxdataxml.sipprofile.PidfPlPassthru
				$objTemp.RecordRouteHdrPref = $uxdataxml.sipprofile.RecordRouteHdrPref
				$objTemp.RedundancyRetryTimer = $uxdataxml.sipprofile.RedundancyRetryTimer
				$objTemp.SDPHandling = $uxdataxml.sipprofile.SDPHandling
				$objTemp.SendAssertHdrAlways = $uxdataxml.sipprofile.SendAssertHdrAlways
				$objTemp.SendNumberofAudioChan = $uxdataxml.sipprofile.SendNumberofAudioChan
				$objTemp.SessionName = $uxdataxml.sipprofile.SessionName
				$objTemp.SessionTimer = $uxdataxml.sipprofile.SessionTimer
				$objTemp.SessionTimerExp = $uxdataxml.sipprofile.SessionTimerExp
				$objTemp.SessionTimerMin = $uxdataxml.sipprofile.SessionTimerMin
				$objTemp.StaticHost = $uxdataxml.sipprofile.StaticHost
				$objTemp.TerminateOnRefreshFailure = $uxdataxml.sipprofile.TerminateOnRefreshFailure
				$objTemp.TimerC = $uxdataxml.sipprofile.TimerC
				$objTemp.TimerD = $uxdataxml.sipprofile.TimerD
				$objTemp.TimerJ = $uxdataxml.sipprofile.TimerJ
				$objTemp.TimerT1 = $uxdataxml.sipprofile.TimerT1
				$objTemp.TimerT2 = $uxdataxml.sipprofile.TimerT2
				$objTemp.TimerT4 = $uxdataxml.sipprofile.TimerT4
				$objTemp.TransportTimeoutTimer = $uxdataxml.sipprofile.TransportTimeoutTimer
				$objTemp.TrustedInterface = $uxdataxml.sipprofile.TrustedInterface
				$objTemp.UnknownPlPassthru = $uxdataxml.sipprofile.UnknownPlPassthru
				$objTemp.UserAgentHeader = $uxdataxml.sipprofile.UserAgentHeader
				
				$objResult=$objTemp
		
	#This object contains all the sipprofile table objects. Do a foreach to grab friendly names of the sipprofile tables
	$objResult

}

Function global:new-uxsipprofile {
	<#
	.SYNOPSIS      
	 This cmdlet creates a new sip profile (not sipserver table entry)
	 
	.DESCRIPTION
	This cmdlet creates a sip profile (not sipserver table entry).
	
	.PARAMETER Description
	Enter here the Description (Name) of the sipserver table.This is what will be displayed in the Ribbon GUI
	
	.EXAMPLE
	 new-uxsipservertable -Description "LyncToPBX"
	
	#>
	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$false,Position=0)]
		[ValidateLength(1,64)]
		[string]$Description ,

		[Parameter(Mandatory=$true,Position=1)]
		[ValidateLength(1,255)]
		[string]$StaticHost ,

		[Parameter(Mandatory=$true,Position=2)]
		[ValidateLength(1,64)]
		[string]$OriginFieldUserName ,

		[Parameter(Mandatory=$false,Position=3)]
		[ValidateRange(0,3)]
		[int]$FQDNinFromHeader = 3 ,

		[Parameter(Mandatory=$false,Position=4)]
		[ValidateRange(0,3)]
		[int]$FQDNinContactHeader = 3 


	)
        

	
	#DEPENDENCY ON get-uxsipservertable FUNCTION TO GET THE NEXT AVAILABLE SIPSERVER TABLEID
	Try {
		$sipprofileid = ((get-uxsipprofile | select -ExpandProperty id | Measure-Object -Maximum).Maximum)+1
	}
	Catch {
		throw "Command failed when trying to execute the sipprofileid using `"get-uxsipprofile`" cmdlet.The error is $_"
	}
	
	#URL for the new sipserver table
   	$args = "Description=$Description&StaticHost=$StaticHost&OriginFieldUserName=$OriginFieldUserName&FQDNinFromHeader=$FQDNinFromHeader&FQDNinContactHeader=$FQDNinContactHeader"

	$url = "https://$uxhostname/rest/sipprofile/$sipprofileid"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method PUT -Body $args -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	#If table is successfully created, 200OK is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose -Message $uxrawdata
	}
	#If 500 message is returned
	ElseIf ($uxrawdata | select-string "<http_code>500</http_code>"){
		Write-Verbose -Message $uxrawdata
		throw "Unable to create sipserver table. Ensure you have entered a unique sipserver table id"
	}
	#If no 200 or 500 message
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Sanitise data and return as object for verbose only
	Try {
		$m = $uxrawdata.IndexOf("<sipprofile id=")
		$length = ($uxrawdata.length - $m - 8)
		[xml]$uxdataxml =  $uxrawdata.substring($m,$length)
	}
	Catch {
		throw "Unable to convert received data into XML correctly. The error message is $_"
	}
	#Return sipserver table object just created
	write-verbose $uxdataxml.sipprofile
}

#Function to get signalgroup
Function global:get-uxsignalgroup {
	<#
	.SYNOPSIS      
	 This cmdlet displays all the signalgroup names and ID's
	
	.EXAMPLE
	 get-uxsignalgroup
	
	#>

	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$false,Position=0)]
		[int]$signalgroupid

	)

# Check if sipserver table id was added as parameter
 if (-Not $signalgroupid) { 

	
	$url = "https://$uxhostname/rest/sipsg"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method GET -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Check if connection was successful.HTTP code 200 is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose $uxrawdata
		
		#Sanitise data and return as object
		Try {
			$m = $uxrawdata.IndexOf("<sipsg_list")
			$length = ($uxrawdata.length - $m - 8)
			[xml]$uxdataxml =  $uxrawdata.substring($m,$length)
		}
		Catch {
			throw "Unable to convert received data into XML correctly. The error message is $_"
		}
		
	}
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Create template object to hold the values of Tranformation tables
	$objTemplate = New-Object psobject
	$objTemplate | Add-Member -MemberType NoteProperty -Name id -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Description -Value $null
	
	#Create an empty array which will contain the output
	$objResult = @()
		
	#This object contains all the sipprofile table objects. Do a foreach to grab friendly names of the sipprofile tables
	foreach ($objtranstable in $uxdataxml.sipsg_list.sipsg_pk) {
		Try {
		$uxrawdata2 = Invoke-RestMethod -Uri $($objtranstable.href) -Method GET -WebSession $sessionvar -ErrorAction Stop
		}
	
		Catch {
			throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
		}
	
		#Check if connection was successful.HTTP code 200 is returned
		If ( $uxrawdata2 | select-string "<http_code>200</http_code>"){
	
			Write-Verbose $uxrawdata2
		
			#Sanitise data and return as object
			Try {
				$m = $uxrawdata2.IndexOf("<sipsg id=")
				$length = ($uxrawdata2.length - $m - 8)
				[xml]$uxdataxml2 =  $uxrawdata2.substring($m,$length)
				
				#Create template object and stuff all the sipprofile tables into it
				$objTemp = $objTemplate | Select-Object *
				$objTemp.id = $uxdataxml2.sipsg.id
				$objTemp.description = $uxdataxml2.sipsg.description
				$objResult+=$objTemp
			}
			Catch {
				throw "Unable to convert received data into XML correctly. The error message is $_"
			}
			
		}
		Else {
			#Unable to Login
			throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
		}
	
	}
	#This object contains all the sipprofile tables with id to description mapping
	$objResult
}

Else {get-uxsignalgroupid $signalgroupid}

}

#Function to get signalgroupid
Function global:get-uxsignalgroupid {
	<#
	.SYNOPSIS      
	 This cmdlet displays the specified signalgroup ID's
	
	.EXAMPLE
	 get-uxsignalgroupid
	
	#>

	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0,HelpMessage='To find the ID of the signalgroup "get-uxsignalgroup" cmdlet')]
	    	[int]$signalgroupid
	)
	$args1 = ""
	$url = "https://$uxhostname/rest/sipsg/$signalgroupid"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method GET -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Check if connection was successful.HTTP code 200 is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose $uxrawdata
		
		#Sanitise data and return as object
		Try {
			$m = $uxrawdata.IndexOf("<sipsg id=")
			$length = ($uxrawdata.length - $m - 8)
			[xml]$uxdataxml =  $uxrawdata.substring($m,$length)
		}
		Catch {
			throw "Unable to convert received data into XML correctly. The error message is $_"
		}
		
	}
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	

	#Create template object to hold the values of Tranformation tables
	$objTemplate = New-Object psobject
	$objTemplate | Add-Member -MemberType NoteProperty -Name Description -Value $null	
	$objTemplate | Add-Member -MemberType NoteProperty -Name customAdminState -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ProfileID -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Channels -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ServerSelection -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ServerClusterId -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RelOnQckConnect -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RelOnQckConnectTimer -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RTPMode -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RTPProxyMode -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RTPDirectMode -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name VideoProxyMode -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name VideoDirectMode -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name MediaConfigID -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ToneTableID -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ActionSetTableID -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RouteTableID -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RingBack -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name HuntMethod -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Direction -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name PlayCongestionTone -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Early183 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name AllowRefreshSDP -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name OutboundProxy -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ProxyIpVersion -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name NoChannelAvailableId -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TimerSanitySetup -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TimTimerCallProceeding -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ChallengeRequest -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name NotifyCACProfile -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name NonceLifetime -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Monitor -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name AuthorizationRealm -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ProxyAuthorizationTableID -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RegistrarID -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RegistrarTTL -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name OutboundRegistrarTTL -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name DSCP -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ListenPort_1 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Protocol_1 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TLSProfileID_1 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name LocalIP_1 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ListenPort_2 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Protocol_2 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TLSProfileID_2 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name LocalIP_2 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ListenPort_3 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Protocol_3 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TLSProfileID_3 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name LocalIP_3 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ListenPort_4 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Protocol_4 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TLSProfileID_4 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name LocalIP_4 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ListenPort_5 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Protocol_5 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TLSProfileID_5 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name LocalIP_5 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ListenPort_6 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Protocol_6 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name TLSProfileID_6 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name LocalIP_6 -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name SIPtoQ850_TableID -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Q850toSIP_TableID -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name NetInterfaceSignaling -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name NATTraversalType -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name NATPublicIPAddress -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name PassthruPeerSIPRespCode -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name SGLevelMOHService -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name IngressSPRMessageTableList -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name EgressSPRMessageTableList -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name QoEReporting -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name VoiceQualityReporting -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RegisterKeepAlive -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name InteropMode -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name AgentType -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RegistrantTTL -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ADAttribute -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ADUpdateFrequency -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ADFirstUpdateTime -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name Office365FQDN -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name ICESupport -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name InboundNATTraversalDetection -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name InboundNATQualifiedPrefixesTableID -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name InboundSecureNATMediaLatching -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name InboundSecureNATMediaPrefix -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name InboundNATPeerRegistrarMaxEnabled -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name InboundNATPeerRegistrarMaxTTL -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RemoteHosts -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name RemoteMasks -Value $null
	$objTemplate | Add-Member -MemberType NoteProperty -Name SIPReSync -Value $null

	
	#Create an empty array which will contain the output
	$objResult = @()

		
	#Create template object and stuff all the sipprofile values into it
				$objTemp = $objTemplate | Select-Object *
                $objTemp.description = $uxdataxml.sipsg.description
                $objTemp.customAdminState = $uxdataxml.sipsg.customAdminState
                $objTemp.ProfileID = $uxdataxml.sipsg.profileid
                $objTemp.Channels = $uxdataxml.sipsg.Channels
                $objTemp.ServerSelection = $uxdataxml.sipsg.ServerSelection
                $objTemp.ServerClusterId = $uxdataxml.sipsg.ServerClusterId
                $objTemp.RelOnQckConnect = $uxdataxml.sipsg.RelOnQckConnect
                $objTemp.RelOnQckConnectTimer = $uxdataxml.sipsg.RelOnQckConnectTimer
                $objTemp.RTPMode = $uxdataxml.sipsg.RTPMode
                $objTemp.RTPProxyMode = $uxdataxml.sipsg.RTPProxyMode
                $objTemp.RTPDirectMode = $uxdataxml.sipsg.RTPDirectMode
                $objTemp.VideoProxyMode = $uxdataxml.sipsg.VideoProxyMode
                $objTemp.VideoDirectMode = $uxdataxml.sipsg.VideoDirectMode
                $objTemp.MediaConfigID = $uxdataxml.sipsg.MediaConfigID
                $objTemp.ToneTableID = $uxdataxml.sipsg.ToneTableID
                $objTemp.ActionSetTableID = $uxdataxml.sipsg.ActionSetTableID
                $objTemp.RouteTableID = $uxdataxml.sipsg.RouteTableID
                $objTemp.RingBack = $uxdataxml.sipsg.RingBack
                $objTemp.HuntMethod = $uxdataxml.sipsg.HuntMethod
                $objTemp.Direction = $uxdataxml.sipsg.Direction
                $objTemp.PlayCongestionTone = $uxdataxml.sipsg.PlayCongestionTone
                $objTemp.Early183 = $uxdataxml.sipsg.Early183
                $objTemp.AllowRefreshSDP = $uxdataxml.sipsg.AllowRefreshSDP
                $objTemp.OutboundProxy = $uxdataxml.sipsg.OutboundProxy
                $objTemp.ProxyIpVersion = $uxdataxml.sipsg.ProxyIpVersion
                $objTemp.ProxyIpVersion = $uxdataxml.sipsg.ProxyIpVersion
                $objTemp.NoChannelAvailableId = $uxdataxml.sipsg.NoChannelAvailableId
                $objTemp.TimerSanitySetup = $uxdataxml.sipsg.TimerSanitySetup
                $objTemp.TimTimerCallProceeding = $uxdataxml.sipsg.TimTimerCallProceeding
                $objTemp.ChallengeRequest = $uxdataxml.sipsg.ChallengeRequest
                $objTemp.NotifyCACProfile = $uxdataxml.sipsg.NotifyCACProfile
                $objTemp.NonceLifetime = $uxdataxml.sipsg.NonceLifetime
                $objTemp.Monitor = $uxdataxml.sipsg.Monitor
                $objTemp.AuthorizationRealm = $uxdataxml.sipsg.AuthorizationRealm
                $objTemp.ProxyAuthorizationTableID = $uxdataxml.sipsg.ProxyAuthorizationTableID
                $objTemp.RegistrarID = $uxdataxml.sipsg.RegistrarID
                $objTemp.RegistrarTTL = $uxdataxml.sipsg.RegistrarTTL
                $objTemp.OutboundRegistrarTTL = $uxdataxml.sipsg.OutboundRegistrarTTL
                $objTemp.DSCP = $uxdataxml.sipsg.DSCP
                $objTemp.ListenPort_1 = $uxdataxml.sipsg.ListenPort_1
                $objTemp.Protocol_1 = $uxdataxml.sipsg.Protocol_1
                $objTemp.TLSProfileID_1 = $uxdataxml.sipsg.TLSProfileID_1
                $objTemp.LocalIP_1 = $uxdataxml.sipsg.LocalIP_1
                $objTemp.ListenPort_2 = $uxdataxml.sipsg.ListenPort_2
                $objTemp.Protocol_2 = $uxdataxml.sipsg.Protocol_2
                $objTemp.TLSProfileID_2 = $uxdataxml.sipsg.TLSProfileID_2
                $objTemp.LocalIP_2 = $uxdataxml.sipsg.LocalIP_2
                $objTemp.ListenPort_3 = $uxdataxml.sipsg.ListenPort_3
                $objTemp.Protocol_3 = $uxdataxml.sipsg.Protocol_3
                $objTemp.TLSProfileID_3 = $uxdataxml.sipsg.TLSProfileID_3
                $objTemp.Protocol_3 = $uxdataxml.sipsg.Protocol_3
                $objTemp.LocalIP_3 = $uxdataxml.sipsg.LocalIP_3
                $objTemp.ListenPort_4 = $uxdataxml.sipsg.ListenPort_4
                $objTemp.Protocol_4 = $uxdataxml.sipsg.Protocol_4
                $objTemp.TLSProfileID_4 = $uxdataxml.sipsg.TLSProfileID_4
                $objTemp.LocalIP_4 = $uxdataxml.sipsg.LocalIP_4
                $objTemp.ListenPort_5 = $uxdataxml.sipsg.ListenPort_5
                $objTemp.Protocol_5 = $uxdataxml.sipsg.Protocol_5
                $objTemp.TLSProfileID_5 = $uxdataxml.sipsg.TLSProfileID_5
                $objTemp.LocalIP_5 = $uxdataxml.sipsg.LocalIP_5
                $objTemp.ListenPort_6 = $uxdataxml.sipsg.ListenPort_6
                $objTemp.Protocol_6 = $uxdataxml.sipsg.Protocol_6
                $objTemp.TLSProfileID_6 = $uxdataxml.sipsg.TLSProfileID_6
                $objTemp.LocalIP_6 = $uxdataxml.sipsg.LocalIP_6
                $objTemp.SIPtoQ850_TableID = $uxdataxml.sipsg.SIPtoQ850_TableID
                $objTemp.Q850toSIP_TableID = $uxdataxml.sipsg.Q850toSIP_TableID
                $objTemp.NetInterfaceSignaling = $uxdataxml.sipsg.NetInterfaceSignaling
                $objTemp.NATTraversalType = $uxdataxml.sipsg.NATTraversalType
                $objTemp.NATPublicIPAddress = $uxdataxml.sipsg.NATPublicIPAddress
                $objTemp.PassthruPeerSIPRespCode = $uxdataxml.sipsg.PassthruPeerSIPRespCode
                $objTemp.SGLevelMOHService = $uxdataxml.sipsg.SGLevelMOHService
                $objTemp.IngressSPRMessageTableList = $uxdataxml.sipsg.IngressSPRMessageTableList
                $objTemp.EgressSPRMessageTableList = $uxdataxml.sipsg.EgressSPRMessageTableList
                $objTemp.QoEReporting = $uxdataxml.sipsg.QoEReporting
                $objTemp.VoiceQualityReporting = $uxdataxml.sipsg.VoiceQualityReporting
                $objTemp.RegisterKeepAlive = $uxdataxml.sipsg.RegisterKeepAlive
                $objTemp.InteropMode = $uxdataxml.sipsg.InteropMode
                $objTemp.AgentType = $uxdataxml.sipsg.AgentType
                $objTemp.RegistrantTTL = $uxdataxml.sipsg.RegistrantTTL
                $objTemp.ADAttribute = $uxdataxml.sipsg.ADAttribute
                $objTemp.ADUpdateFrequency = $uxdataxml.sipsg.ADUpdateFrequency
                $objTemp.ADFirstUpdateTime = $uxdataxml.sipsg.ADFirstUpdateTime
                $objTemp.Office365FQDN = $uxdataxml.sipsg.Office365FQDN
                $objTemp.ICESupport = $uxdataxml.sipsg.ICESupport
                $objTemp.InboundNATTraversalDetection = $uxdataxml.sipsg.InboundNATTraversalDetection
                $objTemp.InboundNATQualifiedPrefixesTableID = $uxdataxml.sipsg.InboundNATQualifiedPrefixesTableID
                $objTemp.InboundSecureNATMediaLatching = $uxdataxml.sipsg.InboundSecureNATMediaLatching
                $objTemp.InboundSecureNATMediaPrefix = $uxdataxml.sipsg.InboundSecureNATMediaPrefix
                $objTemp.InboundNATPeerRegistrarMaxEnabled = $uxdataxml.sipsg.InboundNATPeerRegistrarMaxEnabled
                $objTemp.InboundNATPeerRegistrarMaxTTL = $uxdataxml.sipsg.InboundNATPeerRegistrarMaxTTL
                $objTemp.RemoteHosts = $uxdataxml.sipsg.RemoteHosts
                $objTemp.RemoteMasks = $uxdataxml.sipsg.RemoteMasks
                $objTemp.SIPReSync = $uxdataxml.sipsg.SIPReSync


				$objResult=$objTemp
		
	#This object contains all the signalgroup table objects. Do a foreach to grab friendly names of the sipprofile tables
	$objResult

}

#Function to create new signalgroup
Function global:new-uxsignalgroup {
	<#
	.SYNOPSIS      
	 This cmdlet creates a new signalgroup
	 
	.DESCRIPTION
	This cmdlet creates a sip new signalgroup
	
	.PARAMETER Description
	Enter here the Description (Name) of the sipserver table.This is what will be displayed in the Ribbon GUI
	
	.EXAMPLE
	 new-uxsignalgroup -Description "LyncToPBX"
	
	#>
	[cmdletbinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0,HelpMessage='Short description/name of the SG')]
		[ValidateLength(1,64)]
		[string]$Description ,

		[Parameter(Mandatory=$true,Position=1,HelpMessage='Enable or Disable this signaling group')]
		[ValidateSet(0,1)]
		[int]$customAdminState = 1 ,

		[Parameter(Mandatory=$true,Position=1,HelpMessage='Enable or Disable this signaling group')]
		[ValidateRange(1,65534)]
		[int]$ProfileID = 6 ,

		[Parameter(Mandatory=$true,Position=2,HelpMessage='Specifies the number of SIP channels available for call')]
		[ValidateRange(1,960)]
		[int]$Channels = 10 ,

		[Parameter(Mandatory=$true,Position=3,HelpMessage='Specifies the Media List to be used by this Signaling Group')]
		[ValidateRange(1,65534)]
		[int]$MediaConfigID ,

		[Parameter(Mandatory=$true,Position=4,HelpMessage='Specifies the Call Routing Table to be used by this Signalling Group')]
		[ValidateRange(1,65534)]
		[int]$RouteTableID ,

		[Parameter(Mandatory=$false,Position=5,HelpMessage='Specifies the local listen port 1 on which SG can receive message. This needs to be provided if Protocol_1 is present')]
		[ValidateRange(0,65535)]
		[int]$ListenPort1 = 5067 ,

		[Parameter(Mandatory=$false,Position=6,HelpMessage='Protocol type used by the listener. Currently only 1,2 and 4 are being used. This needs to be provided if ListenPort_1 is present')]
		[ValidateRange(0,9)]
		[int]$Protocol1 = 2 ,

		[Parameter(Mandatory=$false,Position=7,HelpMessage='If protocol is TLS this is the id of TLS profile in use')]
		[ValidateRange(0,65534)]
		[int]$TLSProfileID1 ,

		[Parameter(Mandatory=$true,Position=8,HelpMessage='Specifies the interface name followed by -1 for primary, followed by -2 for secondary IP')]
		[ValidateLength(7,60)]
		[string]$NetInterfaceSignaling ,

		[Parameter(Mandatory=$false,Position=9,HelpMessage='Comma separated list of remote IPs or subnet from which SG can receive requests')]
		[ValidateLength(7,2500)]
		[string]$RemoteHosts ,

		[Parameter(Mandatory=$false,Position=10,HelpMessage='Comma separated list of subnet masks for the IP Addresses specified in RemoteHosts above')]
		[ValidateLength(7,2500)]
		[string]$RemoteMasks = "255.255.255.255" 
	

	)
        

	
	#DEPENDENCY ON get-uxsipservertable FUNCTION TO GET THE NEXT AVAILABLE signalgroup ID
	Try {
		$sipsgid = ((get-uxsignalgroup | select -ExpandProperty id | Measure-Object -Maximum).Maximum)+1
	}
	Catch {
		throw "Command failed when trying to execute the sipprofileid using `"get-uxsipprofile`" cmdlet.The error is $_"
	}
	$sipsgid
    #Setting required variables
    $RelOnQckConnect=0
    $RTPMode=1
    $RTPProxyMode=1
    $RTPDirectMode=1
    $VideoProxyMode=0
    $VideoDirectMode=0
    $HuntMethod=4
    $ProxyIpVersion=0
    $DSCP=40
    $NATTraversalType=0
    $ICESupport=0
    $ICEMode=0
    $InboundNATTraversalDetection=0

    #Default for non required parameters
    $ServerSelection = 0
    $ServerClusterId = 6
    $RelOnQckConnectTimer = 1000
    $ToneTableID = 0
    $ActionSetTableID = 0
    $RingBack = 0
    $Direction = 2
    $PlayCongestionTone = 0
    $Early183 = 0
    $AllowRefreshSDP = 1
    $OutboundProxy = ""
    $OutboundProxyPort = 5060
    $NoChannelAvailableId = 34
    $TimerSanitySetup = 180000
    $TimerCallProceeding = 180000
    $ChallengeRequest = 0
    $NotifyCACProfile = 0
    $NonceLifetime = 600
    $Monitor = 2
    $AuthorizationRealm = ""




	#URL for the new ssignal group
   	#$args = "description=$description&customadminstate=$customadminstate&profileid=$ProfileID&channels=$channels&mediaconfigid=$mediaconfigid&routetableid=$routetableid&listenport1=$listenport1&protocol1=$protocol1&tlsprofileid1=$tlsprofileid1&netinterfacesignaling=$netinterfacesignaling&remotehosts=$remotehosts&remotemasks=$remotemasks&relonqckconnect=$relonqckconnect&rtpmode=$rtpmode&rtpproxymode=$rtpproxymode&rtpdirectmode=$rtpdirectmode&videoproxymode=$videoproxymode&videodirectmode=$videodirectmode&huntmethod=$huntmethod&proxyipversion=$proxyipversion&dscp=$dscp&nattraversaltype=$nattraversaltype&icesupport=$icesupport&inboundnattraversaldetection=$inboundnattraversaldetection&icemode=$icemode&ServerClusterId=$ServerClusterId"
    $args ="SIPReSync=0&InboundNATPeerRegistrarMaxTTL=120&InboundNATPeerRegistrarMaxEnabled=0&InboundSecureNATMediaPrefix=255.255.255.255&InboundSecureNATMediaLatching=1&InboundNATQualifiedPrefixesTableID=0&InboundNATTraversalDetection=0&ADUpdateFrequency=1&ADAttribute= pager&RegistrantTTL=3600&AgentType=0&InteropMode=0&RegisterKeepAlive=1&SGLevelMOHService=0&PassthruPeerSIPRespCode=1&NATTraversalType=0&NetInterfaceSignaling= Ethernet 2-1&TLSProfileID_1=2&Protocol_1=4&ListenPort_1=5067&DSCP=40&OutboundRegistrarTTL=600&RegistrarTTL=600&RegistrarID=0&ProxyAuthorizationTableID=0&AuthorizationRealm= &Monitor=3&NonceLifetime=0&NotifyCACProfile=0&ChallengeRequest=0&TimerSanitySetup=255000&NoChannelAvailableId=34&ProxyIpVersion=0&AllowRefreshSDP=1&Early183=0&PlayCongestionTone=0&Direction=2&HuntMethod=4&RingBack=0&RouteTableID=2&ActionSetTableID=0&ToneTableID=1&MediaConfigID=2&VideoDirectMode=0&VideoProxyMode=0&RTPDirectMode=1&RTPProxyMode=1&RTPMode=1&RelOnQckConnectTimer=1000&RelOnQckConnect=0&ServerClusterId=2&ServerSelection=0&Channels=10&ProfileID=19&customAdminState=1&Description=test"
	$url = "https://$uxhostname/rest/sipsg/$sipsgid"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method PUT -Body $args -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	#If table is successfully created, 200OK is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose -Message $uxrawdata
	}
	#If 500 message is returned
	ElseIf ($uxrawdata | select-string "<http_code>500</http_code>"){
		Write-Verbose -Message $uxrawdata
		throw "Unable to create signalgroup. Ensure you have entered a unique signalgroup id"
	}
	#If no 200 or 500 message
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Sanitise data and return as object for verbose only
	Try {
		$m = $uxrawdata.IndexOf("<sipprofile id=")
		$length = ($uxrawdata.length - $m - 8)
		[xml]$uxdataxml =  $uxrawdata.substring($m,$length)
	}
	Catch {
		throw "Unable to convert received data into XML correctly. The error message is $_"
	}
	#Return sipserver table object just created
	write-verbose $uxdataxml.sipsg
}

#Function to restartUX
Function global:restart-uxgateway {
	<#
	.SYNOPSIS      
	 This cmdlet restarts Ribbon gateway
	 
	.SYNOPSIS      
	This cmdlet restarts Ribbon gateway
	
	.EXAMPLE
	 restart-uxgateway
	
	#>

	[cmdletbinding()]
	Param()
	$args1 = ""
	$url = "https://$uxhostname/rest/system?action=reboot"
	
	Try {
		$uxrawdata = Invoke-RestMethod -Uri $url -Method POST -Body $args1 -WebSession $sessionvar -ErrorAction Stop
	}
	
	Catch {
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
	
	#Check if reboot command was accepted.HTTP code 200 is returned
	If ( $uxrawdata | select-string "<http_code>200</http_code>"){
	
		Write-Verbose $uxrawdata
		
		#Sanitise data and return as object
		Try {
			$m = $uxrawdata.IndexOf("<sipprofiletable_list")
			$length = ($uxrawdata.length - $m - 8)
			[xml]$uxdataxml =  $uxrawdata.substring($m,$length)
		}
		Catch {
			throw "Unable to convert received data into XML correctly. The error message is $_"
		}
		
	}
	Else {
		#Unable to Login
		throw "Unable to process this command.Ensure you have connected to the gateway using `"connect-uxgateway`" cmdlet or if you were already connected your session may have timed out (10 minutes of no activity).The error message is $_"
	}
}

