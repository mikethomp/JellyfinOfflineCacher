[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$JellyfinHost,
    [Parameter(Mandatory = $true)][string]$JellyfinUser,
    [Parameter(Mandatory = $true)][string]$ApiKey,
    [Parameter()][switch]$SyncSpecialsFirst
)

Import-Module JellyfinPS -Force

# Get the user
$User = Get-JellyfinUser -UserName $JellyfinUser -JellyfinHost $JellyfinHost -ApiKey $ApiKey
Write-Verbose "User Id: $($User.Id)"

# Setup directory structure
if (!(Test-Path ~/Jellyfin)) {
    New-Item -Path ~/Jellyfin -ItemType Directory | Out-Null
}
if (!(Test-Path ~/Jellyfin/subscriptions.json)) {
    $Subscriptions = @()
} else {
    $Subscriptions = @(Get-Content ~/Jellyfin/subscriptions.json | ConvertFrom-Json)
}

function Read-Choice {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][array]$Choices,
        [Parameter()][string]$Prompt,
        [Parameter()][ValidateRange(0, [int]::MaxValue)][int]$DefaultChoiceIndex = 0
    )

    if ($Choices.Count -eq 1) {
        return [PSCustomObject]@{
            Index = 0
            Value = $Choices[0]
        }
    } else {
        if (!$Prompt) {
            $Prompt = "Choose"
        }

        if ($DefaultChoiceIndex -gt ($Choices.Count - 1)) {
            $DefaultChoiceIndex = 0
        }
        
        if ($Choices.Count -eq 1) {
            $ChoicePrompt = "$($Prompt) [1]".Trim()
        } else {
            $ChoicePrompt = "$($Prompt) (1-$($Choices.Count)) [$($DefaultChoiceIndex + 1)]".Trim()
        }
        
        $Choice = $null
        do {
            Write-Host ""
            foreach ($Index in 0..($Choices.Count - 1)) {
                Write-Host "$($Index + 1) - $($Choices[$Index])"
            }

            $UserChoice = (Read-Host -Prompt $ChoicePrompt).Trim()
            if (!$UserChoice.Trim()) {
                $UserChoice = "$(($DefaultChoiceIndex + 1))"
            }
                
            $UserChoiceInt = 0
            
            if ([int]::TryParse($UserChoice, [ref]$UserChoiceInt)) {
                if ($UserChoiceInt -in 1..$Choices.Count) {
                    $Choice = [PSCustomObject]@{
                        Index = ($UserChoiceInt - 1)
                        Value = $Choices[($UserChoiceInt - 1)]
                    }
                }
            }
            if (!$Choice) {
                Write-Host ""
                Write-Warning "Invalid input received."
            }
        } until ($Choice)

        return $Choice
    }
}

do {

    # Main Menu
    $MenuChoices = @('New Subscription')
    if ($Subscriptions) {
        $MenuChoices += 'View Subscriptions'
    }
    $MenuChoices += 'Exit'

    $MenuChoice = Read-Choice -Choices $MenuChoices -Prompt "Main Menu"
    Write-Host $MenuChoice.Value -ForegroundColor DarkGreen

    # New Subscription
    if ($MenuChoice.Value -eq "New Subscription") {

        # Search Jellyfin
        do {
            do {
                $SearchString = Read-Host -Prompt "Enter Search Term"
            } until ($SearchString.Trim())

            $SearchResults = @(@(Search-Jellyfin `
                -SearchTerm $SearchString `
                -UserId $User.Id `
                -JellyfinHost $JellyfinHost `
                -ApiKey $ApiKey `
                -Movies -Shows) | Where-Object {
                    # Exclude any items that are already subscribed
                    !($_.Id -in @($Subscriptions.Id))
                })
            if (!$SearchResults) {
                Write-Warning "No search results found, try again!"
            }
        } until ($SearchResults)

        # Choose and item from the results
        $ChosenResult = Read-Choice -Choices @(@($SearchResults | ForEach-Object {
                "$($_.Name) ($(($_.Type -eq "Series") ? "Show" : $_.Type))"
            }) + @('Back')) -Prompt "Subscript To"
        
        # Save the Subscription
        if ($ChosenResult.Value -ne "Back") {
            Write-Host "Subscribed to $($SearchResults[$ChosenResult.Index].Name)"
            
            $Subscriptions += [PSCustomObject]@{
                Name           = $SearchResults[$ChosenResult.Index].Name
                Id             = $SearchResults[$ChosenResult.Index].Id
                Type           = $SearchResults[$ChosenResult.Index].Type
                Bitrate        = $null
                SyncedItems = 0
            }

            ConvertTo-Json -InputObject $Subscriptions -Depth 100 | Out-File ~/Jellyfin/subscriptions.json
        }
    }

    # View subscriptions
    if ($MenuChoice.Value -eq "View Subscriptions") {
        do {

            #Choose a Subscription
            $ChosenSubscription = Read-Choice -Choices (@($Subscriptions | ForEach-Object {
                        "$($_.Name) ($(($_.Type -eq "Series") ? "Show [$($_.SyncedItems)]" : "$($_.Type) [$($_.SyncedItems)]"))"
                    }) + @('Back')) -Prompt "Choose Subscription"
            
            if ($ChosenSubscription.Value -ne "Back") {
                Write-Host $ChosenSubscription.Value -ForegroundColor Green

                do {
                    # Choose an action for the subscription
                    $SubscriptionActionChoices = @('Sync Subscription', 'Remove Subscription')
                    if ($Subscriptions[$ChosenSubscription.Index].SyncedItems) {
                        $SubscriptionActionChoices += "Play"
                    }
                    $SubscriptionActionChoices += "Back"
                    $ChosenSubscriptionAction = Read-Choice -Choices $SubscriptionActionChoices

                    # Sync the subscription with the Jellyfin Server
                    if ($ChosenSubscriptionAction.Value -eq 'Sync Subscription') {
                        
                        # Choose the Bitrate
                        if (!$Subscriptions[$ChosenSubscription.Index].Bitrate) {
                            $Subscriptions[$ChosenSubscription.Index].Bitrate = [int64]"720Kb"
                        }
                        $DefaultChoiceIndex = @([int64]"420Kb", [int64]"720Kb", [int64]"1.5Mb", [int64]"3Mb", [int64]"4Mb").IndexOf($Subscriptions[$ChosenSubscription.Index].Bitrate)
                        if ($DefaultChoiceIndex -eq -1) {
                            $Subscriptions[$ChosenSubscription.Index].Bitrate = [int64]"720Kb"
                            $DefaultChoiceIndex = 1
                        }
                        $Subscriptions[$ChosenSubscription.Index].Bitrate = [int64](Read-Choice -Choices @("420Kb", "720Kb", "1.5Mb", "3Mb", "4Mb") -Prompt "Choose Quality" -DefaultChoiceIndex $DefaultChoiceIndex).Value
                        ConvertTo-Json -InputObject $Subscriptions -Depth 100 | Out-File ~/Jellyfin/subscriptions.json
                        
                        # Is this a Series or Movie?
                        if ($Subscriptions[$ChosenSubscription.Index].Type -eq "Series") {
                            
                            #Get all the seasons of the show
                            $Seasons = @((Get-JellyfinSeasons `
                                        -ShowId $Subscriptions[$ChosenSubscription.Index].Id `
                                        -JellyfinHost $JellyfinHost `
                                        -ApiKey $ApiKey `
                                        -UserId $User.Id) | Where-Object { !$_.UserData.Played })
                            
                            # This makes sure any specials are the last videos to sync (unless "Display specials within seasons they aired in" is enabled).
                            if (!$SyncSpecialsFirst) {
                                $SeasonsSorted = @(@($Seasons | Where-Object { $_.IndexNumber -ne 0 }) + @($Seasons | Where-Object { $_.IndexNumber -eq 0 }))
                            } else {
                                $SeasonsSorted = $Seasons
                            }
                            
                            # Iterate through the seasons
                            $EpisodesOutput = @()
                            foreach ($Season in $SeasonsSorted) {
                                
                                # Get Episodes that have not yet been played
                                $Episodes = @((Get-JellyfinEpisodes `
                                    -ShowId $Subscriptions[$ChosenSubscription.Index].Id `
                                    -SeasonId $Season.Id `
                                    -JellyfinHost $JellyfinHost `
                                    -ApiKey $ApiKey `
                                    -UserId $User.Id) | Where-Object { !$_.UserData.Played })
                                
                                # Download the first 5 unplayed episodes
                                foreach ($Episode in $Episodes) {
                                    $EpisodesOutput += [PSCustomObject]@{
                                        Name = "S$("$($Season.IndexNumber)".PadLeft(2, "0"))E$("$($Episode.IndexNumber)".PadLeft(2, "0")) - $($Episode.Name)"
                                        Id   = $Episode.Id
                                    }

                                    if (!((Test-Path "~/Jellyfin/$($Subscriptions[$ChosenSubscription.Index].Id)/$($Episode.Id).mp4"))) {
                                        Invoke-JellyfinVideoDownload `
                                            -VideoId $Episode.Id `
                                            -OutputDirectory "~/Jellyfin/$($Subscriptions[$ChosenSubscription.Index].Id)" `
                                            -JellyfinHost $JellyfinHost `
                                            -ApiKey $ApiKey `
                                            -Bitrate $Subscriptions[$ChosenSubscription.Index].Bitrate | Out-Null
                                    }
                                    
                                    if ($EpisodesOutput.Count -ge 5) {
                                        break
                                    }
                                }

                                if ($EpisodesOutput.Count -ge 5) {
                                    break
                                }
                            }

                            # Update and save the .json files
                            ConvertTo-Json -InputObject $EpisodesOutput -Depth 100 | Out-File "~/Jellyfin/$($Subscriptions[$ChosenSubscription.Index].Id)/episodes.json"
                            $Subscriptions[$ChosenSubscription.Index].SyncedItems = $EpisodesOutput.Count
                            ConvertTo-Json -InputObject $Subscriptions -Depth 100 | Out-File ~/Jellyfin/subscriptions.json

                            # Remove any old files
                            Get-ChildItem "~/Jellyfin/$($Subscriptions[$ChosenSubscription.Index].Id)" -Filter *.mp4 | Where-Object {
                                !($_.BaseName -in @($EpisodesOutput.Id))
                            } | ForEach-Object {
                                Write-Host "Removing $($_.FullName)..." -ForegroundColor Red
                                Remove-Item $_ -Force
                            }
                        } else {

                            # If it's a movie, we just always sync it
                            if (!((Test-Path "~/Jellyfin/$($Subscriptions[$ChosenSubscription.Index].Id)/$($Subscriptions[$ChosenSubscription.Index].Id).mp4"))) {
                                Invoke-JellyfinVideoDownload `
                                    -VideoId $Subscriptions[$ChosenSubscription.Index].Id `
                                    -OutputDirectory "~/Jellyfin/$($Subscriptions[$ChosenSubscription.Index].Id)" `
                                    -JellyfinHost $JellyfinHost `
                                    -ApiKey $ApiKey `
                                    -Bitrate $Subscriptions[$ChosenSubscription.Index].Bitrate | Out-Null
                                
                                # Update and save the .json files
                                $Subscriptions[$ChosenSubscription.Index].SyncedItems = 1
                                ConvertTo-Json -InputObject $Subscriptions -Depth 100 | Out-File ~/Jellyfin/subscriptions.json
                            }
                        }
                    }

                    # Remove a subscription
                    if ($ChosenSubscriptionAction.Value -eq 'Remove Subscription') {

                        # Remove it from the subscriptions.json
                        $Subscriptions = @($Subscriptions | Where-Object { $_.Id -ne $Subscriptions[$ChosenSubscription.Index].Id })
                        ConvertTo-Json -InputObject $Subscriptions -Depth 100 | Out-File ~/Jellyfin/subscriptions.json

                        # Delete the associated files
                        Get-ChildItem ~/Jellyfin -Directory | Where-Object {
                            !($_.BaseName -in @($Subscriptions.Id))
                        } | ForEach-Object {
                            Write-Host "Removing $($_.FullName)..." -ForegroundColor Red
                            Remove-Item $_ -Force -Recurse
                        }
                        $ChosenSubscriptionAction.Value = "Back"
                    }

                    # Play a subscription
                    if ($ChosenSubscriptionAction.Value -eq 'Play') {

                        if ($Subscriptions[$ChosenSubscription.Index].Type -eq "Series") {
                            #For shows, choose from the list of synced episodes until Back is chosen
                            do {
                                $Episodes = @(Get-Content "~/Jellyfin/$($Subscriptions[$ChosenSubscription.Index].Id)/episodes.json" | ConvertFrom-Json)
                                $PlayEpisode = Read-Choice -Prompt "Choose Episode" -Choices @(@($Episodes.Name) + @("Back"))
                                
                                if ($PlayEpisode.Value -ne "Back") {
                                    Write-Host "Playing $($PlayEpisode.Value)..." -ForegroundColor Green
                                    $EpisodeFile = Get-Item "~/Jellyfin/$($Subscriptions[$ChosenSubscription.Index].Id)/$($Episodes[$PlayEpisode.Index].Id).mp4" 
                                    Start-Process -FilePath vlc -ArgumentList "--fullscreen", $EpisodeFile.FullName -Wait | Out-Null
                                }
                            } until ($PlayEpisode.Value -eq "Back")
                        } else {
                            # For movies, just go ahead and play the movie
                            $MovieFile = Get-Item "~/Jellyfin/$($Subscriptions[$ChosenSubscription.Index].Id)/$($Subscriptions[$ChosenSubscription.Index].Id).mp4" 
                            Start-Process -FilePath vlc -ArgumentList "--fullscreen", $MovieFile.FullName -Wait | Out-Null
                        }
                    }
                } until ($ChosenSubscriptionAction.Value -eq "Back")
            }
        } until ($ChosenSubscription.Value -eq "Back")
    }
} until ($MenuChoice.Value -eq "Exit")