<#
.SYNOPSIS
Watches the current path for changes to CSharp files and initiates a build of the project.

.DESCRIPTION
Watches the current directory and sub-directories for changes to C-Sharp files; initiating a build of the project to which the changed file belongs.

.EXAMPLE
> cd "D:\path\to\my\project"
> D:\path\to\my\project> Start-CSharp-Watch
#>
function Start-CSharp-Watch() {
    write-host "CSharp-Watch is watching for file changes..." -foregroundcolor "green"

    $existingEvents = get-eventsubscriber
    foreach ($item in $existingEvents) {	    
        if ($item.SourceObject.Path -eq $global:EventSourcePath) {            
            Unregister-event -SubscriptionId $item.SubscriptionId
            write-host "Unsubscribed from: "$item.SourceObject.Path -foregroundcolor Gray
        }
    }

    $global:FileChanged = $false # dirty... any better suggestions?
    $folder = get-location
    $global:EventSourcePath = $folder
    $filter = "*.*"
    $watcher = New-Object IO.FileSystemWatcher $folder, $filter -Property @{ 
        IncludeSubdirectories = $true
        EnableRaisingEvents = $true
    }
    
    Register-ObjectEvent $watcher "Changed" -Action {
        $global:FileChanged = $true
        $global:ChangedPath = $Event.SourceEventArgs.FullPath
    } > $null

    While ($true){
        While ($global:FileChanged -eq $false){
            # We need this to block the IO thread until there is something to run 
            # so the script doesn't finish. If we call the action directly from 
            # the event it won't be able to write to the console
            Start-Sleep -Milliseconds 100
        }        
        # a file has changed, run our stuff on the I/O thread so we can see the output
        if ($global:ChangedPath -match "(\.cs~|.cs$)") {
            # this is the bit we want to happen when the file changes
            write-host "Locating csproj file..." -ForegroundColor darkgreen
            if ($global:ChangedPath) {
                write-host "File was changed: '$global:ChangedPath'" -ForegroundColor darkgreen

                $pathParts = "$global:ChangedPath".Split("\\")
                $end = $pathParts.Count - 2 # skip the file name to the parent directory
                $testPath = $pathParts[0..$end] -join "\"
                write-host "Testing path $testPath" -ForegroundColor darkgreen
                $csproj = Get-ChildItem -path $testPath *.csproj

                For ($i = 0; $i -le 25; $i++) {
                    $newEnd = $end - $i
                    $newPath = $pathParts[0..$newEnd] -join "\"
                    $csproj = Get-ChildItem -path $newPath *.csproj
                    write-host "$i. trying: $newPath, csproj: $csproj" -ForegroundColor darkgreen
                    if ($csproj) {
                        write-host "Found on $i, at $newPath, $csproj" -ForegroundColor darkgreen
                        break
                    }
                }

                if ("$csproj".EndsWith(".csproj")) {
                    write-host "Ready: $newPath\$csproj" -foregroundcolor DarkGreen
                    $msbuild = "C:\Program Files (x86)\MSBuild\14.0\Bin\MSBuild.exe"
                    & $msbuild ("$newPath\$csproj", "/target:Build", "/p:configuration=debug", "/verbosity:m")
                }
            }
        }
        # reset and go again
        $global:FileChanged = $false
    }
}
<#
.SYNOPSIS
Unsubscribes current path from the watch event.

.DESCRIPTION
Unsubscribes current path from the watch event.

.EXAMPLE
> cd "D:\path\to\my\project"
> D:\path\to\my\project> Stop-CSharp-Watch

#>
function Stop-CSharp-Watch() {
    $existingEvents = get-eventsubscriber
    ForEach ($item in $existingEvents) {	    
        if ($item.SourceObject.Path -eq $global:EventSourcePath) {            
            Unregister-event -SubscriptionId $item.SubscriptionId
            write-host "Unsubscribed from: "$item.SourceObject.Path -foregroundcolor Gray
        }
    }
    break
}