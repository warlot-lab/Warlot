package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/steven3002/warlot-publisher/internal/services"
	"github.com/steven3002/warlot-publisher/internal/utils"
)

type AuthHandler struct {
	Signer *services.Signer
}

func NewAuthHandler(signer *services.Signer) *AuthHandler {
	return &AuthHandler{Signer: signer}
}

func (h *AuthHandler) GenerateKeys(c *gin.Context) {
	var req struct {
		Address string `json:"address" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	rawAPIKey, err := utils.GenerateRandomKey()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate API key"})
		return
	}

	rawEncKey, err := utils.GenerateRandomKey()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate encryption key"})
		return
	}

	hashedAPIKey := utils.HashKey(rawAPIKey)
	hashedEncKey := utils.HashKey(rawEncKey)
	signature := h.Signer.Sign(req.Address, rawAPIKey)

	

	c.JSON(http.StatusOK, gin.H{
		"raw_api_key":        rawAPIKey,
		"raw_encrypt_key":    rawEncKey,
		"hashed_api_key":     hashedAPIKey,
		"hashed_encrypt_key": hashedEncKey,
		"signature_hash":     signature,
	})
}


// VerifySignature now takes the expected signature hash from the client,
// recalculates it, and compares.
func (h *AuthHandler) VerifySignature(c *gin.Context) {
    var req struct {
        Address       string `json:"address" binding:"required"`
        APIKey        string `json:"api_key" binding:"required"`
        SignatureHash string `json:"signature_hash" binding:"required"`
    }
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }

    // Pass the expected on-chain (or client-provided) hash into Verify
    valid := h.Signer.Verify(req.Address, req.APIKey, req.SignatureHash)
    c.JSON(http.StatusOK, gin.H{"valid_signature": valid})
}