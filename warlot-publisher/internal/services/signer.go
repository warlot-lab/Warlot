package services

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
)

type Signer struct {
	BackendPrivateKey []byte
}


func (s *Signer) Sign(address, apiKey string) string {
	data := []byte(address + apiKey)
	h := hmac.New(sha256.New, s.BackendPrivateKey)
	h.Write(data)
	return hex.EncodeToString(h.Sum(nil))
}


func (s *Signer) Verify(address, apiKey, expectedHash string) bool {
	newSig := s.Sign(address, apiKey)
	return hmac.Equal([]byte(newSig), []byte(expectedHash))
}
