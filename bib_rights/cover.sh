docker-compose run --rm test perl -MDevel::Cover=-db,/htapps/babel/crms/cover_db /htapps/babel/crms/t/bib_rights.t
docker-compose run --rm test cover /htapps/babel/crms/cover_db
