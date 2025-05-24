package db

import (
	"database/sql"
	"fmt"
	_ "github.com/lib/pq"
	"os"
	"time"
)

func ConnectUserDB() (*sql.DB, error) {
	return sql.Open("postgres", os.Getenv("USER_DATABASE_URL"))
}

func GetUserInfo(userDB *sql.DB, walletAddress string) (name, email string, err error) {
	query := `
        SELECT name, email
          FROM public.users
         WHERE wallet_address = $1
    `
	err = userDB.QueryRow(query, walletAddress).Scan(&name, &email)
	if err == sql.ErrNoRows {
		err = fmt.Errorf("no user found for address %s", walletAddress)
	}
	return
}

// ShouldNotify returns true if we have NOT notified this wallet yet today.
// If it returns true, it also writes/updates last_notified_at = NOW().
func ShouldNotify(userDB *sql.DB, walletAddress string) (bool, error) {
	//Calculate start of today (midnight)
	now := time.Now()
	todayStart := time.Date(
		now.Year(), now.Month(), now.Day(),
		0, 0, 0, 0, now.Location(),
	)

	//Try to get existing timestamp
	var last time.Time
	err := userDB.QueryRow(
		`SELECT last_notified_at FROM public.notification_log WHERE wallet_address = $1`,
		walletAddress,
	).Scan(&last)

	switch {
	case err == sql.ErrNoRows:
		// No entry exists → first notification today
		_, err = userDB.Exec(
			`INSERT INTO public.notification_log (wallet_address, last_notified_at) VALUES ($1, NOW())`,
			walletAddress,
		)
		if err != nil {
			return false, err
		}
		return true, nil

	case err != nil:
		// Some other DB error
		return false, err

	//Entry exists, check date
	default:
		if last.Before(todayStart) {
			// Last notified on a previous day → update timestamp & notify
			_, err = userDB.Exec(
				`UPDATE public.notification_log SET last_notified_at = NOW() WHERE wallet_address = $1`,
				walletAddress,
			)
			if err != nil {
				return false, err
			}
			return true, nil
		}
		// Already notified today
		return false, nil
	}
}
