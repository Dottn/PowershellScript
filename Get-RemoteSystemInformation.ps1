# Remote System Information
# Shows hardware and OS details from a list of PCs
# Thom McKiernan 22/08/2014
# Modified Sivert Solem 17/10/2017

$transcriptPath = (".\{0} ComputerInformation.txt" -f (Get-Date -Format "yyyy-MM-dd HH.mm"))
Clear-Host

# Write results to file
Start-Transcript $transcriptPath 
$ArrComputers = Read-Host "Specify the list of PC names, comma separated. '.' means local system"
$ArrComputers = $ArrComputers.Split(',')

foreach ($Computer in $ArrComputers) {

    $Computer = $Computer.Trim()

    $computerSystem = Get-WmiObject Win32_ComputerSystem -Computer $Computer -ErrorAction SilentlyContinue -ErrorVariable err
    if ($err.count -gt 0) {
        Write-Host "-------------------------------------------------------"
        Write-Host "$Computer unreachable or denies connections." -ForegroundColor Yellow
        Write-Host "-------------------------------------------------------"
        Continue
    }
    $computerBIOS = Get-WmiObject Win32_BIOS -Computer $Computer
    $computerOS = Get-WmiObject Win32_OperatingSystem -Computer $Computer
    $computerCPU = Get-WmiObject Win32_Processor -Computer $Computer
    $computerHDD = Get-WmiObject Win32_LogicalDisk -ComputerName $Computer -Filter drivetype=3
    Write-Host "System Information for: " $computerSystem.Name -BackgroundColor DarkCyan
    "-------------------------------------------------------"
    "Manufacturer: " + $computerSystem.Manufacturer
    "Model: " + $computerSystem.Model
    "Serial Number: " + $computerBIOS.SerialNumber
    if ($computerCPU.Length -gt 1) {
        foreach ($CPU in $computerCPU) {
            "CPUID: " + $CPU.DeviceID        
            "   CPU: " + $CPU.Name
        }
    }
    else {
        "CPU: " + $computerCPU.Name
    }
    if ($computerHDD.Length -gt 1) {
        foreach ($HDD in $computerHDD) {
            "HDD " + $HDD.DeviceID
            "   HDD Capacity: " + "{0:N2}" -f ($HDD.Size / 1GB) + "GB"
            "   HDD Space: " + "{0:P2}" -f ($HDD.FreeSpace / $HDD.Size) + " Free (" + "{0:N2}" -f ($HDD.FreeSpace / 1GB) + "GB)"
        }
    }
    else {
        "HDD Capacity: " + "{0:N2}" -f ($computerHDD.Size / 1GB) + "GB"
        "HDD Space: " + "{0:P2}" -f ($computerHDD.FreeSpace / $computerHDD.Size) + " Free (" + "{0:N2}" -f ($computerHDD.FreeSpace / 1GB) + "GB)"
    }
    "RAM: " + "{0:N2}" -f ($computerSystem.TotalPhysicalMemory / 1GB) + "GB"
    "Operating System: " + $computerOS.caption + ", Service Pack: " + $computerOS.ServicePackMajorVersion
    "User logged In: " + $computerSystem.UserName
    "Last Reboot: " + $computerOS.ConvertToDateTime($computerOS.LastBootUpTime)
    ""
    "-------------------------------------------------------"
}
Stop-Transcript