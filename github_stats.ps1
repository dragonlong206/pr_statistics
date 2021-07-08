[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$repo,
    [ValidateNotNullOrEmpty()]
    [string]$token,
    [ValidateNotNullOrEmpty()]
    [int]$PRfrom,
    [ValidateNotNullOrEmpty()]
    [int]$PRto
)


<#
    .Synopsis
    Print stats of user activity of PRs by Approved, Changes_Requested, Commented or Dismissed.
    Print stats of who has requested changes against another review, and the number of times.
    Ieally would like to include dimissed reviews on PRs that is NOT by a git commit cancelling out existing reviews.
    API cannot do this, perhaps in the future?
    .Parameter Repo
    The "repo" to be used in the format of "org/repo"; such as "fluffy-cakes/azure_egress_nat".
    .Parameter Token
    A user GitHub personal access token scoped to "repo" is required to automate the API calls used.
    .Parameter PRfrom_or_PRto
    The "PRsfrom/to" are integers of PR numbers where the script shall start and end.
    .Description
    The "blocked" variable is a multidimensional array; an array of arrays
        blocked[*][0] = blocked by
        blocked[*][1] = raised by
        blocked[*][2] = count
        blocked[*][3] = dismissed   #<~~ API not able to determine redacted reviews, commented out :(
    The "stats" variable is a multidimensional array; an array of arrays
        stats[*][0] = user
        stats[*][1] = approved
        stats[*][2] = commented
        stats[*][3] = change
        stats[*][4] = dismissed
        stats[*][5] = pr
    .Example
    .\github_activity.ps1 -repo "fluffy-cakes/azure_egress_nat" -token "asdf" -PRfrom 100 -PRto 110
    Output Example
    Name                 PRs   Approved  Commented     Change  Dismissed
    ----                 ---   --------  ---------     ------  ---------
    userName1              0          2          0          1          0
    userName2              0          1          0          0          1
    userName3              0          1          0          0          0
    userName4              1          3          0          0          0
    Blocked by   Raised by       Count
    ----------   ---------       -----
    userName1    userName4           1
    userName2    userName2           2
    userName3    userName4           2
    userName4    userName1           1
#>


$Global:blocked   = @()
$Global:stats     = @()


function Update-Stats {
    [CmdletBinding()]
    param(
        [string]$type,
        [string]$user
    )

    if ($Global:stats.Count -eq 0) {
        switch ($type) {
            "approved"  { $Global:stats += ,@($user, 1, 0, 0, 0, 0) ; Write-Host "-0 APPROVED  $($user)" }
            "commented" { $Global:stats += ,@($user, 0, 1, 0, 0, 0) ; Write-Host "-0 COMMENTED $($user)" }
            "change"    { $Global:stats += ,@($user, 0, 0, 1, 0, 0) ; Write-Host "-0 CHANGE    $($user)" }
            "dismissed" { $Global:stats += ,@($user, 0, 0, 0, 1, 0) ; Write-Host "-0 DISMISSED $($user)" }
            "pr"        { $Global:stats += ,@($user, 0, 0, 0, 0, 1) ; Write-Host "-0 PR        $($user)" }
        }
    } else {
        foreach ($s in $Global:stats) {
            $statsValue = 0
            if ($s[0] -eq $user) {
                switch ($type) {
                    "approved"   { $s[1]++ ; Write-Host "++ APPROVED  $($user)" }
                    "commented"  { $s[2]++ ; Write-Host "++ COMMENTED $($user)" }
                    "change"     { $s[3]++ ; Write-Host "++ CHANGE    $($user)" }
                    "dismissed"  { $s[4]++ ; Write-Host "++ DISMISSED $($user)" }
                    "pr"         { $s[5]++ ; Write-Host "++ PR        $($user)" }
                }
                break
            } else {
                $statsValue = 1
            }
        }
        if ($statsValue -eq 1) {
            switch ($type) {
                "approved"  { $Global:stats += ,@($user, 1, 0, 0, 0, 0) ; Write-Host "-+ APPROVED  $($user)" }
                "commented" { $Global:stats += ,@($user, 0, 1, 0, 0, 0) ; Write-Host "-+ COMMENTED $($user)" }
                "change"    { $Global:stats += ,@($user, 0, 0, 1, 0, 0) ; Write-Host "-+ CHANGE    $($user)" }
                "dismissed" { $Global:stats += ,@($user, 0, 0, 0, 1, 0) ; Write-Host "-+ DISMISSED $($user)" }
                "pr"        { $Global:stats += ,@($user, 0, 0, 0, 0, 1) ; Write-Host "-+ PR        $($user)" }
            }
            $statsValue = 0
        }
    }
}


function Update-Change {
    [CmdletBinding()]
    param(
        [string]$type,
        [string]$userRaised,
        [string]$user
    )

    if ($Global:blocked.Count -eq 0) {
        switch ($type) {
            "change"    { $Global:blocked += ,@($user, $userRaised, 1, 0) }
            # "dismissed" { $Global:blocked += ,@($user, $userRaised, 0, 1) }   #<~~ API not able to determine redacted reviews :(
        }
    } else {
        foreach ($b in $Global:blocked) {
            $blockedValue = 0
            if (($b[0] -eq $user) -and ($b[1] -eq $userRaised)) {
                switch ($type) {
                    "change"     { $b[2]++ }
                    # "dismissed" { $b[3]++ }   #<~~ API not able to determine redacted reviews :(
                }
                break
            } else {
                $blockedValue = 1
            }
        }
        if ($blockedValue -eq 1) {
            switch ($type) {
                "change"    { $Global:blocked += ,@($user, $userRaised, 1, 0) }
                # "dismissed" { $Global:blocked += ,@($user, $userRaised, 0, 1) }   #<~~ API not able to determine redacted reviews :(
            }
            $blockedValue = 0
        }
    }
}


$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Content-Type", "application/json")
$headers.Add("Authorization", "Bearer $token")


foreach ($i in $PRfrom..$PRto) {
    $i

    $url         = "https://api.github.com/repos/" + $repo + "/pulls/" + $i
    $response    = Invoke-RestMethod $url -Method 'GET' -Headers $headers
    Update-Stats -user $response.user.login -type "pr"

    $newUrl      = "https://api.github.com/repos/" + $repo + "/pulls/" + $i + "/reviews"
    $newResponse = Invoke-RestMethod $newUrl -Method 'GET' -Headers $headers

    foreach ($comment in $newResponse) {
        if       ($comment.state -eq "APPROVED"         ) {
            Update-Stats  -user $comment.user.login -type "approved"
        } elseif ($comment.state -eq "COMMENTED"        ) {
            Update-Stats  -user $comment.user.login -type "commented"
        } elseif ($comment.state -eq "CHANGES_REQUESTED") {
            Update-Stats  -user $comment.user.login -type "change"
            Update-Change -user $comment.user.login -userRaised $response.user.login -type "change"
        } elseif ($comment.state -eq "DISMISSED"        ) {
            Update-Stats  -user $comment.user.login -type "dismissed"
            # Update-Change -user $comment.user.login -userRaised $response.user.login -type "dismissed"   #<~~ API not able to determine redacted reviews :(
        }
    }
    $i++
}


$Global:stats | `
    Select-Object -Property `
        @{ Name = 'Name';      Expression = { $_[0] } }, `
        @{ Name = 'Approved';  Expression = { $_[1] } }, `
        @{ Name = 'Commented'; Expression = { $_[2] } }, `
        @{ Name = 'Change';    Expression = { $_[3] } }, `
        @{ Name = 'Dismissed'; Expression = { $_[4] } }, `
        @{ Name = 'PRs';       Expression = { $_[5] } } | `
    Sort-Object   -Property 'Name' | `
    Format-Table  -Property `
        @{ Expression = 'Name'      ; Width = 20 }, `
        @{ Expression = 'PRs'       ; Width = 03 }, `
        @{ Expression = 'Approved'  ; Width = 10 }, `
        @{ Expression = 'Commented' ; Width = 10 }, `
        @{ Expression = 'Change'    ; Width = 10 }, `
        @{ Expression = 'Dismissed' ; Width = 10 }


$Global:blocked | `
    Select-Object -Property `
        @{ Name = 'Blocked by'; Expression = { $_[0] } }, `
        @{ Name = 'Raised by';  Expression = { $_[1] } }, `
        @{ Name = 'Count';      Expression = { $_[2] } } | `
    Sort-Object   -Property 'Blocked by' | `
    Format-Table  -Property `
        @{ Expression = 'Blocked by' }, `
        @{ Expression = 'Raised by'  }, `
        @{ Expression = 'Count'      }