## Function we load in via variable to start-jobs for multi-threading
$intialState = {
    Function Challenge-Trial {
        Param(
            ## All the params we need, passed by main skill-challenge function
            [int] $PassCount,
            [int] $FailCount,
            [int] $DiceChallenge,
            [int] $AverageModifier,
            [int] $DieMaximum,
            [int] $DieMinimum
        )
        ## Initialize Loop Variables
        $fail = 0
        $pass = 0

        ## Trial Loop
        while ( ($fail -lt $FailCount) -and ($pass -lt $PassCount)) # Loop while passes/fails thresholds are below trigger to end trial
        {
            $rand = Get-Random -Maximum $DieMaximum -Minimum $DieMinimum # Grab a value between our die min and max
            $result = ($rand + $AverageModifier - $DiceChallenge) -ge 0 # Get boolean value for our dice roll against DC being greater than or equal to 0 (Roll + Mod vs DC)
            # Check if we pass and increment
            if ($result)
            {$pass++} else {$fail++} 
        } # End of loop to see if we pass or fail the trial

        # Check if we failed or passed and return a 1 only if passed (used to add up success via measure-object, faster then checking through a boolean array)
        if($fail -ge 3){$output = 0}else{$output = 1}
        return $output
    }
}

## Primary Function, this requires a large manditory parameter list to ensure all settings are selected, will prompt if command is called without. 
# Optional Passed/Failed counts to set to calculate the odds of success or failure from any point in the tree.
# Thread count limit and jobs per thread. Gains over 8 threads seem minimal even on 16 thread processor, any ammount over double the threads of the CPU seems to slow it down.
function Skill-Challenge {
    [CmdletBinding()]
    Param(
        [parameter(mandatory=$true)]
        [alias("Count")]
        [int] $TrialCount,
        [parameter(mandatory=$true)]
        [alias("ToPass")]
        [int] $PassCount,
        [parameter(mandatory=$true)]
        [alias("ToFail")]
        [int] $FailCount,
        [parameter(mandatory=$true)]
        [alias("DC")]
        [int] $DiceChallenge,
        [parameter(mandatory=$true)]
        [alias("Mod")]
        [int] $AverageModifier,
        [parameter(mandatory=$true)]
        [alias("Max")]
        [int] $DieMaximum,
        [parameter(mandatory=$true)]
        [alias("Min")]
        [int] $DieMinimum,
        [alias("AlreadyPassed")]
        [int] $Passed = 0,
        [alias("AlreadyFailed")]
        [int] $Failed = 0,
        [int]$ThreadCount = 8,
        [int]$JobsPerThread = 1000
    )
    ## Calculate the number of trials jobs to run and set total trial count off the rounding
    $trialJobsToRun = [Math]::Floor($TrialCount / $JobsPerThread)
    $TrialCount = $trialJobsToRun * $JobsPerThread # This is needed in case the jobs don't divide evenly by trial count, sets trial count to match the ammount that will be ran
    $completedJobs = $null # This will be filled with completed jobs and then itterated through, this is seems to be faster then searching for completed jobs each loop

    ## Run a for loop until we've completed the required trials
    For ($i = 0; $i -lt $trialJobsToRun;$i++)
    {
        ## Store current list of jobs. This will be filled with completed jobs and then itterated through, this is seems to be faster then searching for completed jobs each loop.
        $currentJobs = Get-Job 

        ## Here we stall if we're capped on threads per threadcount variable.
        While ( $currentJobs.count -ge $ThreadCount) # This only works due to grabbing any completed jobs and processing them each loop, otherwise you have to use a where statement to pull out running threads which is slower than count by about a 7-10x factor.
        {
            
            if ($completedJobs)
            {
                ## While we have completed jobs we'll recieve/remove them, then measure their sum as they are just arrays of 0/1. This is many times faster for large arrays then my prior method  of where $true.
                $Passed += (Receive-Job $completedJobs[$j] -AutoRemoveJob -Wait | Measure-Object -Sum).
                $j++ # Since we don't want to keep calling the get-job we'll just itterate using $j, its set in the fail side of this statement.

                ## Check if we've itterated through the completed jobs, if so then null the value to get new jobs on next loop, will exit this loop and spin up more threads as we're no longer above threadcount
                if ($j -ge $completedJobs.count) {$completedJobs = $null} 
                $currentJobs = Get-Job # Gather new job list
            }
            Else # If we don't have completed jobs we should wait a bit and then check for completed jobs again
            {
                sleep -Milliseconds 50 #sleep a bit before checking to not spike the CPU, probably better ways but it works

                ## Gather a new set of jobs for counting threads and checking for any completed jobs
                $currentJobs = Get-Job
                $completedJobs = $currentJobs | ?{$_.State -eq "Completed"}
                $j = 0
            }
        }

        ## Here we start the jobs for multi-threading if we're not locked above at the threadcount limit. Each jobs is just a for loop of multiple trials
        # We have to intialize the script with are function Challenge-Trial, this seems to slow the processes down but i'm unsure how to do it otherwise. 
        Start-Job -InitializationScript $intialState -ScriptBlock {
            for($i = 0; $i -lt $using:JobsPerThread; $i++) # Run trials for JobsPerThread limit
            {Challenge-Trial $using:PassCount $using:FailCount $using:DiceChallenge $using:AverageModifier $using:DieMaximum $using:DieMinimum} # using: lets us call local variables into a script block. This was way too hard to do any other way and is probably not the fastest method
        }
    } # End of for all trials

    ## Wait to process jobs until all our finished then measure and sum the results once we have no more to add. Could do in the above loop with some tuning but the time savings in a future update.
    $Passed += ( (Receive-Job (Get-Job | Wait-Job) )| Measure-Object -Sum).Sum
    ## Clean up all jobs, they should all be complete thus no need to check
    Get-Job | %{Remove-Job $_}
    # Calculate failed based off passed
    $Failed = $TrialCount - $Passed

Write-host "Results of a skill challenge needing $PassCount passes before $FailCount failures with a DC$DiceChallenge, average skill modifier of +$AverageModifier for a D$DieMaximum (min of $DieMinimum)"
Write-host "$($Passed/$TrialCount*100)% trials passed. $Passed of $TrialCount"
}

######################## READ ME ########################
# To use simply type the cmdlet "Skill-Challenge" and it will propmt you for the values, alternatively you can call it as below
# to have all the vairables set in one line.
#
# Skill-Challenge -TrialCount 10000 -PassCount 6 -FailCount 3 -DiceChallenge 15 -AverageModifier 4 -DieMaximum 20 -DieMinimum 1 -ThreadCount 16 -JobsPerThread 1000
# 
#
# For checking how fast it runs with various settings. Useful if you enjoy the numbers
# (Measure-Command{ Skill-Challenge -TrialCount 10000 -PassCount 6 -FailCount 3 -DiceChallenge 15 -AverageModifier 4 -DieMaximum 20 -DieMinimum 1 -ThreadCount 16 -JobsPerThread 1000 }).TotalSeconds
