<#
.SYNOPSIS
Watches the current path for changes to CSharp files and initiates a build of the project.

.DESCRIPTION
Watches the current directory and sub-directories for changes to C-Sharp files; initiating a build of the project to which the changed file belongs.

.PARAMETER copytarget
(Optional) defines an additional target directory where the updated dll gets copied

.EXAMPLE
# Standard call, builds project file
> cd "D:\path\to\my\project"
> D:\path\to\my\project> Start-CSharp-Watch
> -------------------------
# Overload, builds project file and copies dll to the supplied directory
> cd "D:\path\to\my\project"
> D:\path\to\my\project> Start-CSharp-Watch "my" "d:\path\to\my\website\bin"
#>
function Start-CSharp-Watch([Parameter(Mandatory=$false)][string]$copytarget) {    

    $global:robocopytarget = $copytarget
    
    write-host "CSharp-Watch is watching for file changes..." -foregroundcolor Green
    Write-Host "CSharp-Watch target copy path is '$global:robocopytarget'" -ForegroundColor DarkGray

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
            write-host "Locating csproj file..."
            if ($global:ChangedPath) {
                write-host "File was changed: '$global:ChangedPath'"
                $pathParts = "$global:ChangedPath".Split("\\")
                $end = $pathParts.Count - 1
                $testPath = $pathParts[0..$end] -join "\"
                write-host "Testing path $testPath"
                $csproj = Get-ChildItem -path $testPath *.csproj

                For ($i = 0; $i -le 20; $i++) {
                    $newEnd = $end - $i
                    $newPath = $pathParts[0..$newEnd] -join "\"
                    $csproj = Get-ChildItem -path $newPath *.csproj
                    write-host "$i. trying: $newPath, csproj: $csproj"
                    if ($csproj) {
                        write-host "Found on $i, at $newPath, $csproj"
                        break
                    }
                }

                if ("$csproj".EndsWith(".csproj")) {
                    write-host "Ready: $newPath\$csproj"
                    $msbuild = "C:\Program Files (x86)\MSBuild\14.0\Bin\MSBuild.exe"
                    & $msbuild ("$newPath\$csproj", "/target:Build", "/p:configuration=debug", "/verbosity:m", "/p:PostBuildEvent=") # yes, i am skipping post-build events

                    # we have variables to use to try copy the resulting dll, so give it a try
                    if ($global:robocopytarget) {
                        
                        write-host "Copying the binaries to '$global:robocopytarget'"
                        write-host "CSPROJ File directory at '$newPath'"
                        write-host "CSPROJ File file at '$csproj'"
                        $dllName = $csproj -replace ".csproj"
                        #$currentDll = @(Get-ChildItem -Recurse "$newPath" "*$dllName*.dll")[0].FullName
                        write-host "CURRENT DLL is called '$dllName'"
                        robocopy "$newPath\bin" "$global:robocopytarget" "*$dllName*.dll" /NFL /NDL /NJH /nc /ns /np
                    }
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