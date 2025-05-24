package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/steven3002/warlot/warlot-publisher/internal/utils"
)

// AdminAuth checks a special header or HMAC exactly like APIKey, but for admins.
func AdminAuth(adminToken string) gin.HandlerFunc {
	return func(c *gin.Context) {
		tok := utils.HashKey(strings.TrimSpace(c.GetHeader("X-Admin-Token")))

		if tok == "" || tok != adminToken {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "admin auth failed"})
			return
		}
		c.Next()
	}
}
