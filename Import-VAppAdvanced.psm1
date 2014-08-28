##
#
# vElemental
# @clintonskitson
#
# Import-VAppAdvanced.psm1 - Auto-deploy Avamar Virtual Edition
#
##

if(!(Test-Path 'C:\Program Files\VMware\VMware OVF Tool\ovftool.exe')) { Write-Error "OvfTool 3+ 64-bit not installed";pause;break }


#Import-VAppAdvanced -Name AVE-7.0.0.355-02-proxy01 -OvfPath https://ave02.brswh.local/DPNInstalls/downloads/VMWARE_PROXY/AvamarCombinedProxy-linux-sles11_64-7.0.100-355.ova -Net '"Isolated Network"="VLAN995"' -Datastore (Get-Datastore vnx5700-02-nfs-02) -VmHost (Get-VMHost bsg05035.lss.emc.com) -hashProp @{"vami.ip0.EMC_Avamar_Virtual_Machine_Combined_Proxy"="172.16.0.213";"vami.netmask0.EMC_Avamar_Virtual_Machine_Combined_Proxy"="255.255.0.0";"vami.gateway.EMC_Avamar_Virtual_Machine_Combined_Proxy"="172.16.255.254";"vami.DNS.EMC_Avamar_Virtual_Machine_Combined_Proxy"="172.16.255.254"}
function Import-VAppAdvanced {
    [CmdletBinding()]
    param(
        $Name,
        $ovfPath,
        $StorageFormat="Thin",
        $Datastore=$(throw "missing -Datastore"),
        $VmHost=$(throw "missing -VmHost"),
        $Net=$(throw "missing -Net"),
        [hashtable]$hashProp
    )
    Begin {
        Function Get-FullPath {
            [CmdletBinding()]
            param($item)
            Process {
                do {
                    $parent = $item | %{ $_.parent }
                    $parent | select *,@{n="name";e={(Get-View -id "$($_.type)-$($_.value)").name}}
                    if($parent) { $parent | %{ 
                        Get-FullPath (Get-View -id "$($_.type)-$($_.value)") 
                    } }
                    $parent = $null
                } until (!$parent)
            }
        }
    }
    Process {
        
        Write-Host "$(Get-Date): Checking for multiple VCs"
        if($global:DefaultVIServers.count -gt 1) {
            Throw "You are connected to more than one VC, reopen PowerCLI connecting to only one vCenter instance."
        }

        if(!(Test-Path 'C:\Program Files\VMware\VMware OVF Tool\ovftool.exe')) { Write-Error "OvfTool 64-bit not installed";pause;break }

        Write-Host "$(Get-Date): Checking reverse lookup of VC and current VC connection"
        try {
            $vcip = ([System.Net.Dns]::GetHostEntry($global:DefaultVIServer.name)).AddressList[0].IPAddressToString
            $vcreverseName = [System.Net.Dns]::GetHostEntry($vcip).HostName
            if ($vcreverseName -ne $global:DefaultVIServer.name) { 
                 Throw "The reverse DNS name of VC $($vcreverseName) from how you connected to VC as $($global:DefaultVIServer.name) does not match based on resolved IP of $($vcip).  Reload PowerCLI, connecting to $($vcreverseName)"
            }
        } catch {
            Write-Error "Problem with VC forward or reverse lookup"
            Throw $_
        }

        [array]$arrDatastore = Get-VMHost -id $VMhost.id | Get-Datastore | %{ $_.Id }
        if($arrDatastore -notcontains $Datastore.Id) { Throw "Datastore $($Datastore.Name) is not connected to $($VmHost.Name)" }
        
        $NetworkName = $Net.Split("=")[-1].Replace('"','')
        [array]$arrPortGroup = Get-VMHost -id $VMHost.id | Get-VirtualPortGroup | %{ $_.Name }
        if($arrPortGroup -notcontains $NetworkName) { Throw "Networkname $($NetworkName) is not available on $($VmHost.Name)" }


        [array]$arrFullPath = Get-FullPath ($VmHost.Extensiondata)
        $Datacenter = $arrFullPath | where {$_.Type -eq "Datacenter"} | %{ $_.Name }
        $Cluster = $arrFullPath | where {$_.Type -eq "ClusterComputeResource"} | %{ $_.Name }
        

        if($Cluster) {
            $viPath = "vi://$($vcip)/$Datacenter/host/$($Cluster)/$($VmHost.Name)"
        } else {
            $viPath = "vi://$($vcip)/$Datacenter/host/$($VmHost.Name)"
        }

        $Session = Get-View -id SessionManager
        $Ticket=$Session.AcquireCloneTicket()
        
        if($hashProp.keys) {
            [string]$strProp = ($hashProp.keys | %{ 
                $propName = $_
                $propValue = $hashProp.$_
                "--prop:$($propName)='$($propValue)'"
            }) -join " "
        }        

        $command = "& 'C:\Program Files\VMware\VMware OVF Tool\ovftool.exe' --I:targetSessionTicket=$Ticket --diskMode=`"$StorageFormat`" --datastore=`"$($Datastore.Name)`" --name=`"$($Name)`" --noSSLVerify --net:$($net) $strProp `"$OvfPath`" `"$($viPath)`""
        Write-Verbose $command
        Write-Host "$(Get-Date): Uploading OVF"
        try {
            $Output = Invoke-Expression $command

            if($LASTEXITCODE -ne 0) {
                Write-Error "$(Get-Date): Problem durring OVF Upload"
                Throw $Output
            }else {
                Write-Host "$(Get-Date): Successfuly uploaded OVF as $($name)"
            }
        } catch {
            Write-Error "Problem uploading OVF"
            Throw $_
        }
    }        
}

