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
        echo -e "$(timestamp)${INVERSE}${RED}[ERROR]${FRESET}${RED}> $1${FRESET}"
}

warn () {
	echo -e "$(timestamp)${INVERSE}${YELLOW}[WARN]${FRESET}${YELLOW}> $1${FRESET}"
}

CURL="curl -S -s -f"

if [[ -z "$GITEA_TOKEN" ]]; then
	err "GITEA_TOKEN not set. Abort."
	err "Gitea authorization token is required to access gitea organization"
	exit 1;
fi

print_usage_info() {
	echo -e "Usage: $0"
	echo -e "   -o, --org				GitHub organization"
	echo -e "   -v, --visibility {public, private}	Visibility for the created Gitea organization."
	echo -e "   -p, --include-private 		Whether to mirror private repositories"
	echo "" >&2
	exit 1;
}

if [[ -z "$1" ]]; then
	err "No parameters given. Abort."
	print_usage_info
fi

include_private=false
while [[ "$#" -gt 0 ]]; do
        case $1 in
                -o|--org) org_name="$2"; shift ;;
        	-v|--visibility) org_visibility="$2"; shift ;;
        	-p|--include-private) include_private=true ;;
                *) err "Unknown parameter passed: $1"; print_usage_info; exit 1 ;;
        esac
        shift
done

#echo $include_private

#warn $org_name
#warn $org_visibility
#warn $include_private

gitea_header_options=(-H  "Authorization: Bearer ${ACCESS_TOKEN}" -H "accept: application/json" -H "Content-Type: application/json")
jsonoutput=$(mktemp -d -t github-repos-XXXXXXXX)

trap "rm -rf ${jsonoutput}" EXIT


# Fetch list of repos


log "Fetch organization repos."
i=1
# GitHub API just returns empty arrays instead of 404
while $CURL "https://api.github.com/orgs/${org_name}/repos?page=${i}&per_page=100" -u "token:${GITHUB_TOKEN}" >${jsonoutput}/page_${i}.json \
	&& (( $(jq <${jsonoutput}/page_${i}.json '. | length') > 0 )) ; do
	(( i++ && $(cat ${jsonoutput}/page_${i}.json) ))
done

#echo $(jq <${jsonoutput}/page_1.json '.[] | {html:.html_url}')

i=$((i - 1));
echo $i
for page in $(seq 1 $i); do
	n=$(jq '. | length' <${jsonoutput}/page_${page}.json)
	log "Parsing page $page in org $org_name"
	log "$n repos on page $page"
	for repo in $(seq 0 $((n-1))); do 
		repo_data=$(jq ".[${repo}] | {name,html_url,visibility}" <${jsonoutput}/page_${page}.json)
		echo $repo_data
#| jq '.visibility'
	done
done
