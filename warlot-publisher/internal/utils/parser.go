
package utils

import (
	"strings"

	"github.com/steven3002/warlot-publisher/internal/wmodels"
)

// ParseSuccessInfo extracts the SuccessInfo from the raw walrus output.
func ParseSuccessInfo(output string) *wmodels.SuccessInfo {
	info := &wmodels.SuccessInfo{}
	for _, line := range strings.Split(RemoveANSI(output), "\n") {
		s := strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(s, "Success:"):
			info.Message = strings.TrimSpace(strings.TrimPrefix(s, "Success:"))
		case strings.HasPrefix(s, "Path:"):
			info.Path = strings.TrimSpace(strings.TrimPrefix(s, "Path:"))
		case strings.HasPrefix(s, "Blob ID:"):
			info.BlobID = strings.TrimSpace(strings.TrimPrefix(s, "Blob ID:"))
		case strings.HasPrefix(s, "Certification event ID:"):
			info.CertificationEvent = strings.TrimSpace(strings.TrimPrefix(s, "Certification event ID:"))
		case strings.HasPrefix(s, "Expiry epoch"):
			info.ExpiryEpoch = strings.TrimSpace(strings.TrimPrefix(s, "Expiry epoch (exclusive):"))
		case strings.HasPrefix(s, "No blobs were"):
			info.Notes = s
		}
	}
	return info
}

// ParseMetadata fills in additional fields on UploadResponse from raw walrus output.
func ParseMetadata(output string, result *wmodels.UploadResponse) {
	clean := RemoveANSI(output)
	for _, line := range strings.Split(clean, "\n") {
		switch {
		case strings.HasPrefix(line, "Blob ID:"):
			result.BlobID = strings.TrimSpace(strings.TrimPrefix(line, "Blob ID:"))
		case strings.HasPrefix(line, "Sui object ID:"):
			result.SuiObjectID = strings.TrimSpace(strings.TrimPrefix(line, "Sui object ID:"))
		case strings.HasPrefix(line, "Unencoded size:"):
			result.UnencodedSize = strings.TrimSpace(strings.TrimPrefix(line, "Unencoded size:"))
		case strings.HasPrefix(line, "Encoded size:"):
			result.EncodedSize = strings.TrimSpace(strings.TrimPrefix(line, "Encoded size (including replicated metadata):"))
		case strings.HasPrefix(line, "Cost:"):
			result.Cost = strings.TrimSpace(strings.TrimPrefix(line, "Cost (excluding gas):"))
		}
	}
}

