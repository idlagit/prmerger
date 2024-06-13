#!/bin/bash

# declaring job variables
REPO_OWNER="idlagit"
REPO_NAME="prmerger"
TARGET_REPO="https://github.com/$REPO_OWNER/$REPO_NAME.git"
TRIGGER_PHRASE="@dots-schedule-merge"
OPEN_PR_FILE="file_open_prs.txt"
MATCHED_PR_FILE="file_matched_prs.txt"
CHECKS_RESULT_FILE="file_checks_result.txt"
PASSED_PR_FILE="file_passed_prs.txt"
MERGED_PR_FILE="file_merged_prs.txt"
UNMERGED_PR_FILE="file_unmerged_prs.txt"

# step 1: Fetch all open PR's and output $OPEN_PR_FILE
> $OPEN_PR_FILE
gh pr list --repo $TARGET_REPO --state open --json number,reviewDecision,title --jq '.[] | "\(.number) \(.reviewDecision) \(.title)"' > $OPEN_PR_FILE


# step 2: Filter for approved PR's with "@dots-schedule-merge" and output $MATCHED_PR_FILE
if [ ! -s "$OPEN_PR_FILE" ]; then
    echo "Input file '$OPEN_PR_FILE' is empty or missing"
    exit 1
fi

> $MATCHED_PR_FILE

counter=1
while IFS= read -r line; do
    review_decision=$(echo "$line" | awk '{print $2}')        
    if [ "$review_decision" == "APPROVED" ] && [[ "$line" == *"$TRIGGER_PHRASE"* ]]; then
        echo "$line" >> $MATCHED_PR_FILE
        echo "Match found on line $counter"   
    else
        echo "No match found on line $counter"  
    fi
    counter=$((counter+1))

done < $OPEN_PR_FILE
echo ""

# step 3: Run success checks on PR and output $CHECKS_RESULT_FILE & $PASSED_PR_FILE
if [ ! -s "$MATCHED_PR_FILE" ]; then
    echo "Input file '$MATCHED_PR_FILE' is empty or missing"
    exit 1
fi

> $CHECKS_RESULT_FILE
> $PASSED_PR_FILE

while IFS= read -r line; do
    pr_number=$(echo "$line" | awk '{print $1}')
    CHECKS=$(gh pr checks $pr_number --repo $TARGET_REPO --json workflow,state)

    echo "Processing pull request #$pr_number: $pr_title"
    echo $CHECKS | jq -c '.[]'

    echo "pull request #$pr_number results:" >> $CHECKS_RESULT_FILE
    echo $CHECKS | jq -c '.[]' >> $CHECKS_RESULT_FILE
    echo "" >> $CHECKS_RESULT_FILE

    if echo "$CHECKS" | jq -e 'map(select(.state != "SUCCESS")) | length > 0' > /dev/null; then
        echo "Not All Checks Passed for pull request #$pr_number"
    else
        echo "All checks passed for pull request #$pr_number"
        echo $line >> $PASSED_PR_FILE
    fi
    echo ""

done < $MATCHED_PR_FILE


# step 4: Merge pull requests in $PASSED_PR_FILE
if [ ! -s "$PASSED_PR_FILE" ]; then
    echo "Input file '$PASSED_PR_FILE' is empty or missing"
    exit 1
fi
> $MERGED_PR_FILE
> $UNMERGED_PR_FILE

while IFS= read -r line; do
    pr_number=$(echo "$line" | awk '{print $1}')

    echo "Attempting to merge pull request #$pr_number....."
    gh pr merge $pr_number --repo $TARGET_REPO --merge
    
    # checks status to validate that pr is actually merged
    pr_status=$(gh pr view $pr_number --json state | jq -r '.state')

    if [ $pr_status == "MERGED" ]; then
        echo "Pull request #$pr_number sucessfully merged. Current State is '$pr_status'"
        echo "PR #$pr_number" >> $MERGED_PR_FILE
        gh pr comment $pr_number --body "Merged by $TRIGGER_PHRASE"
    else
        echo "Unable to merge #$pr_number. Current State is '$pr_status'"
        echo "PR #$pr_number" >> $UNMERGED_PR_FILE
        gh pr comment $pr_number --body "Failed merge attempt from $TRIGGER_PHRASE"
    fi
done < $PASSED_PR_FILE