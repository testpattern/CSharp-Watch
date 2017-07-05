<#
.SYNOPSIS
Watches the current path for changes to CSharp files and initiates a build of the project.

.DESCRIPTION
Watches the current directory and sub-directories for changes to C-Sharp files; initiating a build of the project to which the changed file belongs.

.PARAMETER copytarget
(Optional) defines an additional target directory where the updated dll gets copied

.EXAMPLE
# Standard call, builds project
> cd "D:\path\to\my\project"
> D:\path\to\my\project> Start-CSharp-Watch
> -------------------------
# Overload, builds project and copies dll to the supplied directory
> cd "D:\path\to\my\project"
> D:\path\to\my\project> Start-CSharp-Watch "d:\path\to\my\website\bin"
#>
function Start-CSharp-Watch([Parameter(Mandatory=$false)][string]$copytarget) {    

    write-host "CSharp-Watch is watching for file changes..."
    Import-Module -Name Invoke-MsBuild

    if ($copytarget) {
        # check the parameter is valid directory
        if ($copytarget -match "^[a-zA-Z]\:\\.+") {
            $global:robocopytarget = $copytarget
            Write-Host "CSharp-Watch will copy updated dlls to: '$global:robocopytarget'"
        } 
        else {
            Write-Host "CSharp-Watch says, 'copytarget is an invalid path'"
        }
    }

    $existingEvents = get-eventsubscriber
    foreach ($item in $existingEvents) {	    
        if ($item.SourceObject.Path -eq $global:EventSourcePath) {
            Unregister-event -SubscriptionId $item.SubscriptionId
            write-host "Unsubscribed from: "$item.SourceObject.Path
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
                    # should test the result and only if succeeded do the copy action
                    $buildresult = Invoke-MsBuild -Path "$newPath\$csproj" -Params "/target:Build /p:configuration=debug /p:PostBuildEvent= /verbosity:m"
                    if ($buildresult.BuildSucceeded) {
                        if ($global:robocopytarget) {
                            # there's a copy target set, so copy the dll to there
                            write-host "Copying the binaries to '$global:robocopytarget'"
                            write-host "CSPROJ File directory at '$newPath'"
                            write-host "CSPROJ File is '$csproj'"
                            $dllName = $csproj -replace ".csproj"
                            write-host "CURRENT Dll is called '$dllName'"
                            robocopy "$newPath\bin" "$global:robocopytarget" "*$dllName*.dll" /NFL /NDL /NJH /nc /ns /np
                        }
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
            write-host "Unsubscribed from: "$item.SourceObject.Path
        }
    }
    break
}