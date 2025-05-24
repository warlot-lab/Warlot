package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/steven3002/warlot/warlot-publisher/internal/blockchain"
	"github.com/steven3002/warlot/warlot-publisher/internal/services"
)

// APIKey returns a Gin middleware that uses the given Signer to verify HMAC signatures.
func APIKey(signer *services.Signer) gin.HandlerFunc {
	// initialize blockchain client once
	suiClient := blockchain.NewClient()

	return func(c *gin.Context) {
		if c.FullPath() == "/generate" || c.FullPath() == "/verify" {
			c.Next()
			return
		}

		// require wallet address
		wallet := c.GetHeader("X-Wallet-Address")
		if strings.TrimSpace(wallet) == "" {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": "missing X-Wallet-Address header"})
			return
		}

		//  require api-key header
		provided := c.GetHeader("X-API-Key")
		if strings.TrimSpace(provided) == "" {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": "missing X-API-Key header"})
			return
		}

		// fetch on-chain expected signature hash
		onChainSig, err := suiClient.GetAPIKey(c.Request.Context(), wallet)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
			return
		}

		// verify HMAC(address + apiKey) == onChainSig
		if !signer.Verify(wallet, provided, onChainSig) {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid api key signature"})
			return
		}

		c.Next()
	}
}
