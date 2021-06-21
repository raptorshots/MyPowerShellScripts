<# 
.DESCRIPTION
Script to get a list of Stale Branches in Azure DevOps GIT Repo's.

.PREREQUISITES
Should have a valid PAT Token with atleast READ/Write access to Code

.NOTES
Change the $orgName and $personalToken as requried
You can use System Token and Environment variables if running from pipeline
Deletion Log will be saved to BranchDeleted.log.

.WARNING
THIS IS A DESTRUCTIVE OPERATION. This cannot be reverted back unless you have a local copy. You will be solely responsible for any damage caused
Script is given as IS.
#>

#Authorizatioion
$personalToken = "<Your_PAT_TOKEN>" #Use System Token if running in Pipeline
$token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($personalToken)"))
$header = @{authorization = "Basic $token" }



#Configure OrganizatioName as it appears in URL when you access the ADO.
$orgName = "<YourOrgName>"

#Get List of all Projects within Org.
$ProjectListUrl = "https://dev.azure.com/$orgName/_apis/projects?api-version=6.0"
$projectNameList = (Invoke-RestMethod $ProjectListUrl -Method Get -ContentType "application/json" -Headers $header).value


# Set the Target Cut off Date for Stale Branches. Here we set 90 days
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
        #$allBranches = $allBranchInfo.name

        #For Each branch Skip pull request, master branch, tags etc. You can add additional Criteria if any here
        foreach ($branch in $allBranchInfo) { 
            
            $branchName = $branch.Name 

            if ( ($branchName -like "refs/pull*") -or ($branchName -like "refs/tags*") -or ($branchName -eq 'refs/heads/master') ) {
                Write-Output "$branchName is pull/ request tags branch. Skipping"
            }
            else {
                $branchObjectId = $branch.objectID
             
                $completeBranchName = $branchName.Replace('refs/heads/', '')
                $branchInfoURL = "https://dev.azure.com/$orgName/$project/_apis/git/repositories/$repoID/stats/branches?name=$completeBranchName`&api-version=6.0"
                $branchInfo = Invoke-restMethod $branchInfoURL -Method GET -ContentType "application/json" -Headers $header
                

                # Convert stupid ISO dates to human readable dates
                $branchLastUpdated = [datetime]::Parse($branchInfo.commit.committer.date)

                # If branchLast updated Date is less than the target date specified output to screen and proceed for deletion
                if ($branchLastUpdated -lt $targetDate) {
                
                    Write-Output "`n ProjectName is $project and RepoName is $repoName and Branch name is $completeBRanchName and last updated date is $branchLastUpdated" 
                
                    Write-Output "`n Deleted Branch in $project with repoName $repoName and Branch name $completeBRanchName and last updated date is $branchLastUpdated" | Out-file DeletedBranch.txt -Append
                                    
                    
                    ## Logic for Deleting Branch. Remove loop if you want to run in fully automated manner

                    $confirm = Read-host "Do you confirm to delete above branch?? If yes press Y and Press Enter"

                    if ($confirm -eq 'Y') {
                        $requestBody = @"

[  
 {     
    "name": "$branchName",     
    "oldObjectId": "$branchObjectId",     
    "newObjectId": "0000000000000000000000000000000000000000"       
  } 
] 
"@
   
                                      
                        $branchDeleteUrl = "https://dev.azure.com/$orgName/$project/_apis/git/repositories/$repoID/refs?api-version=5.1"
                
                        (Invoke-RestMethod $branchDeleteUrl -Method POST -Body $requestBody -ContentType "application/json" -Headers $Header).value
                
                    }                
                
                
                }
                else { Write-Output "Found $completeBranchName Newer Branch, skipping" }
            }


        }

    }
}

