package mailer

import (
	"fmt"

	"github.com/joho/godotenv"
	"github.com/resend/resend-go/v2"

	"log"
	"math"
	"net/url"
	"os"

	"strings"
)

const WAL_DECIMALS = 9
const WAL_DISPLAY_DECIMALS = 4

func SendFailureEmail(
	fullName, suiAddress, Useremail string,
	required, available uint64,
	epochTarget int,
	emailType int, //1 for renwal, 2 for sync
) {

	godotenv.Load()

	warlotRenewMail := os.Getenv("WARLOT_RENEW_ADDRESS")
	warlotSyncMail := os.Getenv("WARLOT_SYNC_ADDRESS")

	resendApiKey := os.Getenv("RESEND_APIKEY")
	// product log on warlus tesnet
	logoCID := `https://aggregator.walrus-testnet.walrus.space/v1/blobs/1cpPP8WIUVo_HZHChVR_dgNxbayuHeb6E94JZFu1Meg`
	appURL := "https://warlot.app/fund"
	if warlotRenewMail == "" || resendApiKey == "" || warlotSyncMail == "" {
		log.Fatal("Please set WARLOT_RENEW_ADDRESS or resendApiKey environment vars")
	}

	client := resend.NewClient(resendApiKey)

	walletAddress := truncateAddress(suiAddress)

	// Build email
	var email *resend.SendEmailRequest

	switch emailType {
	case 1:
		email = buildRenewalFailedEmail(fullName, walletAddress, required, available, epochTarget, logoCID, appURL, Useremail, warlotRenewMail)
	case 2:
		email = buildSyncFailureEmail(fullName, walletAddress, required, available, logoCID, appURL, Useremail, warlotSyncMail)
	default:
		log.Printf("Failed to create mail: invalid email type")
		return
	}

	// Send
	sent, err := client.Emails.Send(email)
	if err != nil {
		log.Printf("Failed to send email: %v", err)
		return
	}

	fmt.Println("Email sent! ID:", sent.Id)
}

func buildRenewalFailedEmail(
	fullName, wallet string,
	required, available uint64,
	epochTarget int,
	logoCID, appLink, toAddress, warlotDomain string,
) *resend.SendEmailRequest {

	// Capitalize name
	name := capitalizeFullName(fullName)

	// Token conversion
	requiredWAL := convertToWALUp(required)
	availableWAL := convertToWALDown(available)

	html := fmt.Sprintf(`
<div style="font-family:Arial, sans-serif; padding:20px; max-width:600px; margin:auto; border:1px solid #e0e0e0; border-radius:8px;">
  <div style="text-align:center; margin-bottom:13px;">
    <img
      src="%s"
      alt="Warlot Logo"
      style="width: 93%%; height: auto; display: block; margin: 0 auto;"
    >
  </div>
  <h2 style="color:#de1f1f;">⚠️ Blob Epoch Renewal Failed</h2>
  <p>Hello <strong>%s</strong>,</p>
  <p>The automatic renewal of your blob for <strong>epoch %d</strong> could not be completed due to insufficient balance.</p>

  <div style="background-color:#f5f5f5; padding:12px; border-radius:6px; margin:20px 0;">
    <p><strong>Wallet: </strong><code>%s</code></p>
    <p><strong>Epoch Set: </strong> %d</p>
    <p><strong>Required: </strong> %s WAL</p>
    <p><strong>Available: </strong> %s WAL</p>
  </div>

  <p>To continue blob operations, please fund your wallet:</p>
  <div style="text-align:center; margin-top:20px;">
    <a href="%s" style="background-color:#1976d2; color:white; text-decoration:none; padding:12px 24px; border-radius:6px; display:inline-block;">
      💳 Fund Wallet
    </a>
  </div>

  <p style="margin-top:30px;">– The Warlot Team</p>
</div>
`, logoCID, // %s
		name,                // %s
		epochTarget,         // %d
		wallet,              // %s
		epochTarget,         // %d
		requiredWAL,         // %s
		availableWAL,        // %s
		htmlEscape(appLink), // %s
	)

	return &resend.SendEmailRequest{
		From:    warlotDomain,
		To:      []string{toAddress},
		Subject: fmt.Sprintf("Epoch Renewal Failed (Epoch %d)", epochTarget),
		Html:    html,
	}
}

func buildSyncFailureEmail(fullName, wallet string,
	required, available uint64,
	logoCID, appLink, toAddress, warlotDomain string) *resend.SendEmailRequest {

	html := fmt.Sprintf(`
<div style="font-family:Arial,sans-serif;background:#e0e0e0;padding:20px;">
  <div style="max-width:600px;margin:auto;background:#fff;border-radius:8px;overflow:hidden;">
    <div style="text-align:center; margin-bottom:0px;">
    <img
      src="%s"
      alt="Warlot Logo"
      style="width: 93%%; height: auto; display: block; margin: 0 auto;"
    >
  </div>
    <div style="padding:20px;">
      <h2 style="color:#ffffff;background:#d32f2f;padding:12px;border-radius:4px;">❌ Sync Failed</h2>
      <p>Hello <strong>%s</strong>,</p>
      <p>We attempted to sync your blob but it failed due to insufficient balance.</p>

      <div style="background:#f5f5f5;padding:12px;border-radius:6px;margin:20px 0;">
        <p><strong>Wallet:</strong> %s</p>
        <p><strong>Required:</strong> %s WAL</p>
        <p><strong>Available:</strong> %s WAL</p>
      </div>

      <div style="text-align:center;margin-top:20px;">
        <a href="%s" style="background:#1976d2;color:#fff;text-decoration:none;
           padding:12px 24px;border-radius:6px;display:inline-block;">
          💳 Fund Wallet
        </a>
      </div>

      <p style="margin-top:30px;">– The Warlot Team</p>
    </div>
  </div>
</div>`, logoCID, fullName, wallet, convertToWALUp(required), convertToWALDown(available), htmlEscape(appLink))

	return &resend.SendEmailRequest{
		From:    warlotDomain,
		To:      []string{toAddress},
		Subject: "Sync Failed for Your Blob on Warlot",
		Html:    html,
	}
}

func capitalizeFullName(fullName string) string {
	parts := strings.Fields(fullName)
	for i, part := range parts {
		if len(part) > 0 {
			parts[i] = strings.ToUpper(part[:1]) + strings.ToLower(part[1:])
		}
	}
	return strings.Join(parts, " ")
}

func convertToWALDown(value uint64) string {
	floatVal := float64(value) / math.Pow(10, WAL_DECIMALS)
	result := math.Floor(floatVal*math.Pow(10, WAL_DISPLAY_DECIMALS)) / math.Pow(10, WAL_DISPLAY_DECIMALS)
	return fmt.Sprintf("%.4f", result)
}

func convertToWALUp(value uint64) string {
	floatVal := float64(value) / math.Pow(10, WAL_DECIMALS)
	result := math.Ceil(floatVal*math.Pow(10, WAL_DISPLAY_DECIMALS)) / math.Pow(10, WAL_DISPLAY_DECIMALS)
	return fmt.Sprintf("%.4f", result)
}

func htmlEscape(raw string) string {
	return url.QueryEscape(raw)
}

// truncateAddress returns "0xABCD…WXYZ" from a full address.
func truncateAddress(addr string) string {
	if len(addr) < 10 || !strings.HasPrefix(addr, "0x") {
		return addr
	}
	return addr[:6] + "…" + addr[len(addr)-4:]
}
