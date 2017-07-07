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
> D:\path\to\my\project> Start-CSharp-Watch -copytarget "d:\path\to\my\website\bin"
> -------------------------
# Overload, builds project, copies dll to the supplied directory and hits url
> cd "D:\path\to\my\project"
> D:\path\to\my\project> Start-CSharp-Watch -copytarget "d:\path\to\my\website\bin" -urltarget "http://localhost:50123"
#>
function Start-CSharp-Watch([Parameter(Mandatory=$false)][string]$copytarget, [Parameter(Mandatory=$false)][string]$urltarget) {

    write-host "CSharp-Watch is watching for file changes..."
    Import-Module -Name Invoke-MsBuild

    if ($copytarget) {
        # check the parameter is valid directory
        if ($copytarget -match "^[a-zA-Z]\:\\.+") {
            $global:copytarget = $copytarget
            Write-Host "CSharp-Watch will copy updated dlls to: '$global:copytarget'"
        } 
        else {
            Write-Host "CSharp-Watch says, 'copytarget is an invalid path'"
        }
    }
    
    if ($urltarget) {
        # check the parameter is valid directory
        if ($urltarget -match "^http[s]?\:\/\/.+") {
            $global:urltarget = $urltarget
            Write-Host "CSharp-Watch will make a request after build/copy to: '$global:urltarget'"
        } 
        else {
            Write-Host "CSharp-Watch says, 'urltarget is an invalid, should be in form e.g. http://localsite.me'"
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
        $mypath = $Event.SourceEventArgs.FullPath
        if ($mypath -match "(\.cs~|.cs$)") {
            $global:ChangedPath = $mypath
            Write-Host "SET GLOBAL VALUE: $global:ChangedPath" -f Green
        }
    } > $null

    While ($true){
        While ($global:FileChanged -eq $false){
            # We need this to block the IO thread until there is something to run 
            # so the script doesn't finish. If we call the action directly from 
            # the event it won't be able to write to the console
            Start-Sleep -Milliseconds 250
        }

        # a file has changed, run our stuff on the I/O thread so we can see the output
        # Visual Studio creates a temp file like Code.cs~98jfiodjf.tmp
        if ($global:ChangedPath -match "(\.cs~|.cs$)") {
            $localchangedpath = $global:ChangedPath
            $global:ChangedPath = "nowhere"
            write-host "File was changed: '$localchangedpath'" -f Yellow
            $pathParts = "$localchangedpath".Split("\\")

            For ($i = $pathParts.Length - 2; $i -gt 0; $i--) {
                $newPath = $pathParts[0..$i] -join "\"
                if (test-path $newPath) {
                    $csproj = Get-ChildItem -path $newPath -filter *.csproj
                    write-host "$i. trying: $newPath, csproj: $csproj"
                    if ($csproj) {
                        write-host "Found on $i, at $newPath, $csproj"
                        break
                    }
                }
            }

            if ("$csproj".EndsWith(".csproj")) {
                write-host "Ready: $newPath\$csproj"                                        
                $buildresult = Invoke-MsBuild -Path "$newPath\$csproj" -Params "/target:Build /p:configuration=debug /p:PostBuildEvent= /verbosity:m"

                if ($buildresult.BuildSucceeded) {                    
                    write-host "Build was successful"

                    if ($global:copytarget) {
                        # there's a copy target set, so copy the dll to there
                        write-host "Copying the binaries to '$global:copytarget'"
                        write-host "CSPROJ File directory at '$newPath'"
                        write-host "CSPROJ File is '$csproj'"
                        $dllname = $csproj -replace ".csproj"
                        write-host "CURRENT Dll is called '$dllName'"
                        # it's possible that the project config doesn't put this direct in the \bin ... but, e.g. bin\debug
                        # this is a bit hokey, it would be nice to be able to recursively find the item...
                        # but, there are so many possible configurations, so just check bin or bin\debug for now
                        $target = @(Get-ChildItem -Path "$newPath\bin\*$dllName*.dll")[0]
                        $dllpath = ""
                        if ($target) { 
                            $dllpath = "$newPath\bin"
                        } 
                        else {
                            $dllpath = "$newPath\bin\Debug"
                        }                            
                        $copyjob = start-job { robocopy "$dllpath" "$global:copytarget" "*$dllname*.dll" } -Name copyjob                            
                        $copyjobEvent = Register-ObjectEvent $copyjob StateChanged -Action {
                            Write-Host ('Job {0} complete (copied {1} to {2}).' -f $sender.Name, $csproj, $copytarget)
                            $copyjobEvent | Unregister-Event
                        }
                    }

                    if ($global:urltarget) {
                        Write-Host "Hit uri: '$global:urltarget'"
                        $webjob = start-job { Invoke-WebRequest -uri "$global:urltarget" -TimeoutSec 180 } -Name webjob                            
                        $webjobevent = Register-ObjectEvent $webjob StateChanged -Action {
                            Write-Host ('Job {0} complete (requested uri: {1}).' -f $sender.Name, $global:urltarget)
                            $webjobevent | Unregister-Event
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