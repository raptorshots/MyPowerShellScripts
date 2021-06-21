<# 
.DESCRIPTION
Script to get a list of Stale Branches in Azure DevOps GIT Repo's.

.PREREQUISITES
Should have a valid PAT Token with atleast READ and Status access to Code

.NOTES
Change the $orgName and $personalToken as requried
You can use System Token and Environment variables if running from pipeline
Use Powershell ISE and place the script in somepath like C:\Script instead of a UNC path for better compatibility

#>

#Authorization
$personalToken = "<YOUR_PAT_TOKEN>" #Use System Token if running in Pipeline
$token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($personalToken)"))
$header = @{authorization = "Basic $token" }



#Configure Organization Name as it appears in URL when you access the ADO.
$orgName = "YOUR_ORG_NAME"

#Get List of all Projects within Org.
$ProjectListUrl = "https://dev.azure.com/$orgName/_apis/projects?api-version=6.0"
$projectNameList = (Invoke-RestMethod $ProjectListUrl -Method Get -ContentType "application/json" -Headers $header).value

#Very Manual way of Creating a CSV File. 
Write-Output "ProjectName,RepoName,BranchName,CommitterEmail,LastUpdatedDate" | Out-file BranchInfo.csv

# Set the Target Cut off Date for Stale Branches. HEre Set to 90 days.
$targetDate = (Get-date).AddDays(-90)

#Create a list of Project Name
$projectName = $projectNameList.name


#Loop in each Project 
Foreach ($project in $projectName) {

    #Get complete repo list in each project
    $repolistURL = "https://dev.azure.com/$orgName/$project/_apis/git/repositories?api-version=6.0"
    $repoList = (Invoke-RestMethod $repolistURL -Method Get -ContentType "application/json" -Headers $header).value

    #For each repo Get branches
    Foreach ($repo in $repoList) {
        $repoID = $repo.id
        $repoName = $repo.name
        $allBranchInfoURL = "https://dev.azure.com/$orgName/$project/_apis/git/repositories/$repoID/refs?api-version=6.0"
        $allBranchInfo = (Invoke-RestMethod $allBranchInfoURL -Method Get -ContentType "application/json" -Headers $header).value
        $allBranchNames = $allBranchInfo.name

        #For Each branch Skip pull request, master branch, tags etc. You can add additional Criteria if any here
        foreach ($branchName in $allBranchNames) { 
            if ( ($branchName -like "refs/pull*") -or ($branchName -like "refs/tags*") -or ($branchName -eq 'refs/heads/master') ) {
                Write-Output "$branchName is pull/ request tags branch. Skipping"
            }
            else {
                
                # Hack together a csv
                $completeBranchName = $branchName.Replace('refs/heads/', '')
                $branchInfoURL = "https://dev.azure.com/$orgName/$project/_apis/git/repositories/$repoID/stats/branches?name=$completeBranchName`&api-version=6.0"
                $branchInfo = Invoke-restMethod $branchInfoURL -Method GET -ContentType "application/json" -Headers $header
                $committerEmail = $branchInfo.commit.committer.email

                # Convert stupid ISO dates to human readable dates
                $branchLastUpdated = [datetime]::Parse($branchInfo.commit.committer.date)

                # If branchLast updated Date is less than the target date specified output same to file
                if ($branchLastUpdated -lt $targetDate) {
                
                    Write-Output "ProjectName is $project and RepoName is $repoName and Branch name is $completeBRanchName and last updated date is $branchLastUpdated" 
                
                    Write-Output "$project, $repoName, $completeBranchName, $committerEmail, $branchLastUpdated" | Out-file BranchInfo.csv -Append
                
              
                                      
                
                
                
                
                
                }
                else { Write-Output "Found $completeBranchName Newer Branch, skipping" }
            }


        }

    }
}

#Export and Invoke the CSV File 
Import-Csv .\BranchInfo.csv | Export-Csv -Path BranchLatest.csv
Remove-item .\BranchInfo.csv
Invoke-item .\BranchLatest.csv
