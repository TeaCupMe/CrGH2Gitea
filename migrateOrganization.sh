# GITHUB_TOKEN - Github autorization token with access to private repositories of 
#			organization - required if run with -p option
# GITEA_TOKEN - Gitea authorization token with access to organization repositories
# GITEA_URL - Gitea URL


source ../CrFormatting.sh
#set -euo pipefail

log () {
        echo -e "$(timestamp)[LOG]> $1${FRESET}"
}

err () {
        echo -e "$(timestamp)${INVERSE}${RED}[ERROR]${FRESET}${RED}> $@${FRESET}"
}

success () {
	echo -e "$(timestamp)${INVERSE}${GREEN}[OK]${FRESET}${GREEN}> $1${FRESET}"
}

warn () {
	echo -e "$(timestamp)${INVERSE}${YELLOW}[WARN]${FRESET}${YELLOW}> $1${FRESET}"
}

CURL="curl -S -s -f"

log "Checking required Gitea-related environment variables..."

if [[ -z "$GITEA_TOKEN" ]]; then
	err "GITEA_TOKEN not set. Abort."
	err "Gitea authorization token is required to access gitea organization"
	exit 1;
fi


if [[ -z "$GITEA_URL" ]]; then
	err "GITEA_URL not set. Abort."
	exit 1;
fi

success "Gitea access token found"

print_usage_info() {
	echo -e "Usage: $0"
	echo -e "   -o, --org				GitHub organization"
	echo -e "   -v, --visibility {public, private}	Visibility for the created Gitea organization."
	echo -e "   -p, --include-private 		Whether to mirror private repositories"
	echo "" >&2
	exit 1;
}

log "Checking parameters..."

if [[ -z "$1" ]]; then
	err "No parameters given. Abort."
	print_usage_info
fi

include_private=1
while [[ "$#" -gt 0 ]]; do
        case $1 in
                -o|--org) org_name="$2"; shift ;;
        	-v|--visibility) org_visibility="$2"; shift ;;
        	-p|--include-private) include_private=0 ;;
                *) err "Unknown parameter passed: $1"; print_usage_info; exit 1 ;;
        esac
        shift
done

if [[ ${include_private} -eq 0 ]]; then
	log "Private repositories were selected to be copied, checking GitHub access token"
	if [[ -z "$GITHUB_TOKEN" ]]; then
		err "GITHUB_TOKEN not set, but private repositories are selected to be copied. Abort."
		exit 1
	else
		success "GitHub access token found"
	fi
fi

success "Required parameters set"

gitea_header=(-H  "Authorization: Bearer ${ACCESS_TOKEN}" -H "accept: application/json" -H "Content-Type: application/json")
github_header=(-H "Accept: application/json" -H "Authorization: Bearer ${GITHUB_TOKEN}")

jsonoutput=$(mktemp -d -t github-repos-XXXXXXXX)
trap "rm -rf ${jsonoutput}" EXIT


# Fetch list of repos
log "Fetching organization data..."

$CURL "https://api.github.com/orgs/${org_name}" "${github_header[@]}" >${jsonoutput}/org.data 2>${jsonoutput}/err.log

#cat ${jsonoutput}/err.log

if [[ -s ${jsonoutput}/err.log ]]; then
	cat ${jsonoutput}/org.data
	err "Failed to get organization info. Abort."
	err "More info:"
	err "$(<${jsonoutput}/err.log)"
	exit 1
fi

cat ${jsonoutput}/org.data >./gitout.txt

if [[ $(jq 'try(.public_repos) // -1' <${jsonoutput}/org.data) -eq -1 ]]; then
	err "Error with fetching data about organization"
	err "Check organization name spelling!"
fi
success "Organization found"

if [[ ${include_private} -eq 0 ]]; then
	if [[ $(jq 'try(.total_private_repos) // -1' <${jsonoutput}/org.data) -eq -1 ]]; then
		err "No access to private repositories of ${org_name}"
		err "Maybe GITHUB_TOKEN has expired or does not have the right scope"
		exit 1
	else
		success "Private repositories available"
	fi
else
	log "Public repositories selected"
fi


log "Fetching organization repos"
i=1
# GitHub API just returns empty arrays instead of 404
while $CURL "https://api.github.com/orgs/${org_name}/repos?page=${i}&per_page=100" "${github_header[@]}" >${jsonoutput}/page_${i}.json \
	&& (( $(jq <${jsonoutput}/page_${i}.json '. | length') > 0 )) ; do
	(( i++ ))
#&& $(cat ${jsonoutput}/page_${i}.json) ))
done

#echo $(jq <${jsonoutput}/page_1.json '.[] | {html:.html_url}')

i=$((i - 1));
#echo $i
for page in $(seq 1 $i); do
	n=$(jq '. | length' <${jsonoutput}/page_${page}.json)
	log "Parsing page $page in org $org_name"
	log "$n repos on page $page"
	for repo in $(seq 0 $((n-1))); do 
		repo_data=$(jq ".[${repo}] | {name,html_url,visibility}" <${jsonoutput}/page_${page}.json)
#		log ""
#echo $repo_data
#| jq '.visibility'
	done
done
