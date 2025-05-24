package db

import (
	"database/sql"
	"os"

	_ "github.com/lib/pq"
)

func ConnectBlobDB() (*sql.DB, error) {
	return sql.Open("postgres", os.Getenv("BLOB_DATABASE_URL"))
}
