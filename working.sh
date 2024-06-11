#!/bin/bash
# set -x

TARGET_REPO="https://github.com/idlagit/prmerger.git"

gh pr list --repo $TARGET_REPO --state open --json number,reviewDecision,title --jq '.[] | "\(.number) \(.reviewDecision) \(.title)"' > open_pr.txt

> matched_prs.txt

while IFS= read -r line; do
    review_decision=$(echo "$line" | awk '{print $2}')
    pr_number=$(echo "$line" | awk '{print $1}')
    pr_title=$(echo "$line" | cut -d ' ' -f3-)
        
    echo "Processing pull request #$pr_number: $pr_title"

    if [ "$review_decision" == "APPROVED" ] && [[ "$line" == *"@schedule-merge"* ]]; then

        echo "$line" >> matched_prs.txt
        echo "Added PR #$pr_number: $pr_title to txt file"

        CHECK_RUNS=$(gh pr checks $pr_number --repo $TARGET_REPO --json name,workflow,state,bucket,description)
        # echo $CHECK_RUNS | jq -c '.[]' > check_runs.json

        ALL_CHECKS_PASS=true
        echo "$CHECK_RUNS" | jq -c '.[]' | while IFS= read -r check; do
            result=$(echo "$check" | jq -r '.state')
            workflow=$(echo "$check" | jq -r '.workflow')
            echo "---check:[$workflow] status is $state"

            if [ "$result" != "SUCCESS" ]; then
                ALL_CHECKS_PASS=false
                echo $ALL_CHECKS_PASS
                # echo "Not all checks passed for #$pr_number."
                break
            fi
        done

        if [ "$ALL_CHECKS_PASS" == true ]; then
            echo "All checks passed for pull request #$pr_number."
            echo "Merging pull request #$pr_number ...."
            # gh pr merge $pr_number --repo $TARGET_REPO --merge
        else
            echo "Not all checks passed for #$pr_number."
        fi

    else
        echo "No trigger phrase found in pull request title"
    fi
    echo ""

done < open_pr.txt


