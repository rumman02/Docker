#!/usr/bin/env bash
# Provisions one or more databases per entry in $POSTGRES_SERVICES.
# For each entry <svc> (optionally "<svc>+<db2>,<db3>" to add extra
# databases for the same service):
#   - every listed database is owned by NOLOGIN role <svc>_role
#   - LOGIN role <svc>_user with password from POSTGRES_<SVC>_PASSWORD
#     (uppercased, non-alphanumerics -> _) is granted <svc>_role, so one
#     login reaches all of the service's databases (e.g. an app needing
#     separate auth/users databases).
# Runs on first init only (empty data dir); the entrypoint runs *.sh after
# initdb. Idempotent: existing roles/databases are skipped, existing users
# get their password re-synced from the env.
set -eu

: "${POSTGRES_SERVICES:?POSTGRES_SERVICES must be set (space-separated service names)}"

for svc in $POSTGRES_SERVICES; do
	primary="${svc%%+*}"
	case "$primary" in
		*[!a-z0-9_]*|'') echo "ERROR: invalid service name '$primary' (allowed: a-z 0-9 _)" >&2; exit 1 ;;
	esac

	dbs="$primary"
	case "$svc" in
		*+*)
			extras="${svc#*+}"
			extras="${extras//,/ }"
			for db in $extras; do
				case "$db" in
					*[!a-z0-9_]*) echo "ERROR: invalid extra db name '$db' for service '$primary' (allowed: a-z 0-9 _)" >&2; exit 1 ;;
				esac
			done
			dbs="$primary $extras"
			;;
	esac

	pw_var="POSTGRES_${primary^^}_PASSWORD"
	pw="${!pw_var:-}"
	if [ -z "$pw" ]; then
		echo "ERROR: $pw_var must be set for service '$primary'" >&2
		exit 1
	fi

	psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
		-v svc_role="${primary}_role" -v svc_user="${primary}_user" -v svc_pw="$pw" <<-'EOSQL'
		SELECT 'CREATE ROLE ' || quote_ident(:'svc_role') || ' WITH NOLOGIN'
		WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'svc_role')\gexec
		SELECT 'CREATE ROLE ' || quote_ident(:'svc_user') || ' WITH LOGIN PASSWORD ' || quote_literal(:'svc_pw')
		WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'svc_user')\gexec
		SELECT 'ALTER ROLE ' || quote_ident(:'svc_user') || ' WITH LOGIN PASSWORD ' || quote_literal(:'svc_pw')
		WHERE EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'svc_user')\gexec
		GRANT :"svc_role" TO :"svc_user";
	EOSQL

	for db in $dbs; do
		psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
			-v svc_db="$db" -v svc_role="${primary}_role" <<-'EOSQL'
			SELECT 'CREATE DATABASE ' || quote_ident(:'svc_db') || ' OWNER ' || quote_ident(:'svc_role')
			WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'svc_db')\gexec
			REVOKE ALL ON DATABASE :"svc_db" FROM PUBLIC;
			GRANT ALL PRIVILEGES ON DATABASE :"svc_db" TO :"svc_role";
		EOSQL
	done
done
