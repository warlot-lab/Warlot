package wmodels

import (
	"encoding/json"
	"log"
	"os"
	"sync"
	// "github.com/block-vision/sui-go-sdk/models"
	blockmodels "github.com/block-vision/sui-go-sdk/models"
)

const logFile = "uploads_log.json"

var mu sync.Mutex

type SuccessInfo struct {
	Message            string `json:"message,omitempty"`
	Path               string `json:"path,omitempty"`
	BlobID             string `json:"blob_id,omitempty"`
	CertificationEvent string `json:"certification_event,omitempty"`
	ExpiryEpoch        string `json:"expiry_epoch,omitempty"`
	Notes              string `json:"notes,omitempty"`
}

type UploadResponse struct {
	FileName      string       `json:"file_name"`
	BlobID        string       `json:"blob_id,omitempty"`
	SuiObjectID   string       `json:"sui_object_id,omitempty"`
	Output        *SuccessInfo `json:"output,omitempty"`
	Error         string       `json:"error,omitempty"`
	Timestamp     string       `json:"timestamp"`
	EncodedSize   string       `json:"encoded_size,omitempty"`
	UnencodedSize string       `json:"unencoded_size,omitempty"`
	Cost          string       `json:"cost,omitempty"`

	
	TxDigest      string                           `json:"tx_digest,omitempty"`
	MoveEffects   *blockmodels.SuiEffects `json:"move_effects,omitempty"`
	Deletable     bool                `json:"deletable,omitempty"`

}

// LogUpload appends the upload response to a JSON log file.
func LogUpload(resp *UploadResponse) {
	mu.Lock()
	defer mu.Unlock()

	var existing []UploadResponse
	if data, err := os.ReadFile(logFile); err == nil {
		if err := json.Unmarshal(data, &existing); err != nil {
			log.Printf("Warning: failed to parse existing log: %v", err)
		}
	}

	existing = append(existing, *resp)

	file, err := os.Create(logFile)
	if err != nil {
		log.Printf("Error writing log: %v", err)
		return
	}
	defer file.Close()

	enc := json.NewEncoder(file)
	enc.SetIndent("", "  ")
	if err := enc.Encode(existing); err != nil {
		log.Printf("Error encoding log: %v", err)
	}
}
