package rpc

import (
	"bytes"
	"encoding/json"
	"fmt"
	"github.com/steven3002/Warlot/sui-indexer/pkg/sui"
	"io/ioutil"
	"log"
	"net/http"
	"time"
)

type Client struct {
	endpoint string
}

func NewClient(endpoint string) *Client {
	return &Client{endpoint: endpoint}
}

const (
	packageID     = "0xe0b7c4563c4cdfb71a046931c1b5724192ad515ed33bb73718a414bdd0a200e9"
	moduleName    = "event"
	pageSize      = 50
	descending    = false
	retryInterval = 2 * time.Second
)

func (c *Client) QueryEvents(cursor sui.Cursor) ([]sui.Event, sui.Cursor, error) {
	filter := map[string]interface{}{"MoveEventModule": map[string]string{"package": packageID, "module": moduleName}}
	req := map[string]interface{}{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "suix_queryEvents",
		"params": []interface{}{
			filter,
			cursor,
			pageSize,
			descending,
		},
	}

	payload, err := json.Marshal(req)
	if err != nil {
		return nil, sui.Cursor{}, err
	}

	resp, err := http.Post(c.endpoint, "application/json", bytes.NewReader(payload))
	if err != nil {
		fmt.Println("HTTP error:", err)
		time.Sleep(retryInterval)
		return nil, sui.Cursor{}, err
	}
	body, _ := ioutil.ReadAll(resp.Body)
	defer resp.Body.Close()

	var rpcResp sui.RPCResponse

	if err = json.Unmarshal(body, &rpcResp); err != nil {
		fmt.Println("Decode error:", err)
		time.Sleep(retryInterval)
		return nil, sui.Cursor{}, err
	}

	// if len(rpcResp.Result.Data) == 0 {
	//     fmt.Println("No events found; retrying in", retryInterval)
	//     // time.Sleep(retryInterval)
	// }

	var events []sui.Event
	for _, raw := range rpcResp.Result.Data {

		var ev sui.Event

		// Marshal the raw interface{} back to JSON bytes
		bytesData, err := json.Marshal(raw)
		if err != nil {
			log.Printf("marshal raw data failed: %v", err)
			continue
		}

		// Unmarshal into  Event struct
		if err := json.Unmarshal(bytesData, &ev); err != nil {
			log.Printf("unmarshal to Event failed: %v; data was: %s", err, string(bytesData))
			continue
		}

		// append on successful unmarshal
		events = append(events, ev)

	}

	var nextCursor sui.Cursor
	if rpcResp.Result.NextCursor != nil {
		nextCursor = *rpcResp.Result.NextCursor
	}

	return events, nextCursor, nil
}
