$vcenter = "vCenterFQDN" # Your vCenter name -  vcenter.domain.local
$user = "username" # Your vCenter username - administrator@vsphere.local or domain\username
$password = "password" # Your vCenter password
$uriSlack = "https://..." # Your Slack URI
$location = "Location Title" # Your location title
$reportStyle = 1 # You can change this to 1,2,3 for different view
$action = '*Action*: ' + "Please delete snapshot if you do not need it anymore. Don't keep snapshot more than 24 hours.`n" # You can edit Action message
$title = $emoji + $location + "`n";
try {
    Disconnect-VIServer -server * -confirm:$false
}
catch {
    #"Could not find any of the servers specified by name."
}
$emoji = ':warning:'
$emojiInfo = ':information_source:'
$body = ""
Connect-VIServer -Server $vcenter -User $user -Password $password | out-null
$snapshotList = Get-VM | Get-Snapshot | Where-Object { $_.Created -lt (Get-Date).AddDays(-1) }
$vmNames = ""
$snapshotCreator = ""

function sendSnapshotInfo {
    param([string]$vmName, [string]$snapshotName, [string]$snapshotDesc, [string]$createdDate, [string]$eventCreator, [string]$vmNames)
    switch ($reportStyle) {
        1 {
            $body = @"
{
	"blocks": [
		{
			"type": "section",
			"text": {
				"type": "mrkdwn",
				"text": "This snapshot can now be deleted if not needed!\n*<https://$vcenter|$location>*"
			}
		},
		{
			"type": "section",
			"fields": [
				{
					"type": "mrkdwn",
					"text": "*Virtual Machine:*\n$vmName"
				},
				{
					"type": "mrkdwn",
					"text": "*Created Date:*\n$createdDate"
				},
				{
					"type": "mrkdwn",
					"text": "*Snapshot:*\n$snapshotName"
				},
				{
					"type": "mrkdwn",
					"text": "*Snapshot Creator:*\n$eventCreator"
				},
				{
					"type": "mrkdwn",
					"text": "*Description:*\n$snapshotDesc"
				}
			]
		}
	]
}
"@
        }
        2 {
            $body = ConvertTo-Json @{
                text = $emojiInfo + '*Virtual Machine*: ' + $vmName + "`n" + $emojiInfo + '*Snapshot*: ' + $snapshotName + "`n" + $emojiInfo + '*Description*: ' + $snapshotDesc + "`n" + $emojiInfo + '*Created Date*: ' + $createdDate + "`n" + $emojiInfo + '*Snapshot Creator*: ' + $eventCreator + "`n" + $emojiInfo + '*Location*: ' + $vcenter + "`n" + $emojiInfo + $action
            }
        }
        3 { 

            $body = ConvertTo-Json @{
                text = $title + $vmNames + $action
                
            }
        }
    }
    Invoke-RestMethod -uri $uriSlack -Method Post -body $body -ContentType 'application/json' | Out-Null
    Write-Host "You can check your Slack." $currentHost -ForegroundColor Cyan
}

if ($snapshotList.Length -ne 0) {
    foreach ($vm in $snapshotList) {
        if ($reportStyle -eq 3) {
            $vmNames = $vm.VM.Name + " >" + " Snapshot Name: " + $vm.Name + " >" + " Created Date :" + $vm.Created + "`n"
        }
        else {
            $getSnapshotEvent = Get-VIEvent -Entity $vm.VM -Types Info -Finish $vm.Created -MaxSamples 1 | Where-Object { $_.FullFormattedMessage -imatch 'Task: Create virtual machine snapshot' }
            if ($null -ne $getSnapshotEvent) { 
                Write-Host ( "VM: " + $vm.VM + ". Snapshot '" + $vm + "' created on " + $vm.Created.DateTime + " by " + $getSnapshotEvent.UserName + ".")
                $snapshotCreator = $getSnapshotEvent.UserName
                $snapshotCreator = $snapshotCreator.Replace("\","\\")
            }
            else { 
                Write-Host ("VM: " + $vm.VM + ". Snapshot '" + $vm + "' created on " + $vm.Created.DateTime + ". Can not find the event in vCenter database")
                $snapshotCreator = "User not found."
            }
        }
        sendSnapshotInfo $vm.VM.Name $vm.Name $vm.Description $vm.Created $snapshotCreator $vmNames
    }
}

Disconnect-VIServer -server * -confirm:$false 
