#load credentials
$username = "<user>"
$pwdTxt = Get-Content "encpwd.txt"
$securePwd = $pwdTxt | ConvertTo-SecureString 
$credObject = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $securePwd

#ignore errors
$ErrorActionPreference = 'SilentlyContinue'

#load json
$records=Get-Content .\dns.config|ConvertFrom-Json

#set default TTL
$defaultTTL=[int]$records.defaultTTL

#connect to server
$psSession=New-PSSession -ComputerName $($records.dnsserver) -Credential $credObject -UseSSL
if(-not($psSession))
{
    Write-Warning "$($records.dnsserver) inaccessible!"
}
else
{
	#import external zones and records
	$externalZones=$records.locationzones
	foreach($zone in $externalZones){
		foreach($dnsrecord in $zone.hosts){
			$zonelocation=$zone.locationzone
			Invoke-Command -Session $psSession -scriptblock {
				$zoneLocTest=Get-DnsServerDnsSecZoneSetting -ZoneName $Using:zonelocation
				if($zoneLocTest -eq $null)
				{
					write-host "zone $Using:zonelocation does not exist...creating...."
					Add-DnsServerPrimaryZone -Name $Using:zonelocation -ReplicationScope "Forest" 
				}
				$dnsPrefix=$Using:dnsrecord.prefix
				$dnsAlias=$Using:dnsrecord.alias
				$zoneLoc=$Using:zonelocation
				write-host "Creating record=Name:$Using:dnsprefix alias:$Using:dnsalias zonelocation=$Using:zoneLoc"
				Add-DnsServerResourceRecordCName -Name $Using:dnsrecord.prefix -HostNameAlias $Using:dnsrecord.alias -ZoneName $Using:zonelocation -TimeToLive $Using:defaultTTL
			}
		}
	}
	
	#import internal zones and records
	$internalZones=$records.internalzones
	foreach($zone in $internalZones){
		foreach($environment in $zone.environments){
			$zonelocation=$environment.name+'.'+$zone.internalzone
			write-host "zonelocation:$zonelocation"
            Invoke-Command -Session $psSession -scriptblock {
				$zoneLocTest=Get-DnsServerDnsSecZoneSetting -ZoneName $Using:zonelocation
                if($zoneLocTest -eq $null)
				{
					write-host "zone $Using:zonelocation does not exist...creating...."
					Add-DnsServerPrimaryZone -Name $Using:zonelocation -ReplicationScope "Forest" 
				}
				
				write-host "Creating record=Name:$dnsprefix alias:$dnsalias zonelocation=$zoneLoc"
				Add-DnsServerResourceRecordCName -Name $Using:dnsrecord.prefix -HostNameAlias $Using:dnsrecord.alias -ZoneName $Using:zonelocation -TimeToLive $Using:defaultTTL
			}
            foreach($record in $zone.records){
                write-host ("Record: $record")
                $dnsPrefix=$record.prefix
			    $dnsAlias=$record.alias
                $zoneLoc=$zonelocation
                Invoke-Command -Session $psSession -scriptblock {
                    write-host "Creating record=Name:$Using:dnsprefix alias:$Using:dnsalias zonelocation=$Using:zoneLoc"
				    Add-DnsServerResourceRecordCName -Name $Using:dnsprefix -HostNameAlias $Using:dnsalias -ZoneName $Using:zoneLoc -TimeToLive $Using:defaultTTL
                }
            }
		}
	}
}
   