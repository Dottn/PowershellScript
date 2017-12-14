workflow Get-EventLogEntries {
    $lognames = @("Application", "Security", "System")
    foreach -parallel ($log in $lognames) {
        Get-EventLog -LogName $log -Newest 10 |
            Add-Member -NotePropertyName LogName -NotePropertyValue $log -PassThru |
            Select-Object -Property Index, TimeGenerated, LogName, EntryType, Source, InstanceId, Message
    }
}