package sui

type Cursor struct {
    TxDigest string `json:"txDigest,omitempty"`
    EventSeq string `json:"eventSeq,omitempty"`
}

type RPCResponse struct {
    Result struct {
        Data        []interface{} `json:"data"`
        NextCursor  *Cursor       `json:"nextCursor"`
        HasNextPage bool          `json:"hasNextPage"`
    } `json:"result"`
}

type Event struct {
    Type       string                 `json:"type"`
    ParsedJson map[string]interface{} `json:"parsedJson"`
    ID         Cursor                 `json:"id"`
    TIME       string                 `json:"timestampMs"`
}


const (
    EventNewUser        = "::NewUser"
    EventDeposit        = "::Deposit"
    EventManagedBlobs   = "::ManagedBlobs"
    EventWarlotFileStore = "::WarlotFileStore"
    EventRenewDigest    = "::RenewDigest"
    EventBlobUpdate     = "::BlobUpdate"
    EventWithdrawBlob   = "::WithdrawBlob" 

)