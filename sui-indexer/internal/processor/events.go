package processor

import (
    "encoding/json"
    "fmt"
    "strings"
    "time"
    "strconv"
    "github.com/steven3002/Warlot/sui-indexer/pkg/sui"
    "github.com/steven3002/Warlot/sui-indexer/internal/store"
    "github.com/steven3002/Warlot/sui-indexer/internal/rpc"
    "github.com/steven3002/Warlot/sui-indexer/internal/config"
)


type Processor struct {
    store  *store.DB
    client *rpc.Client
    cfg    *config.Config
}

func NewProcessor(db *store.DB, client *rpc.Client, cfg *config.Config) *Processor {
    return &Processor{store: db, client: client, cfg: cfg}
}

func (p *Processor) ProcessBatch(events []sui.Event) {
    for _, ev := range events {
        
        evType := ev.Type
        // txDigest := ev.ID.TxDigest
        timeStamp, err := parseTimestampMs(ev.TIME)
        if err != nil{
            fmt.Println("=============================> ", err)
            return
        }
        
        // fmt.Println("=============================> ", ev)

   
        switch  {
        case strings.HasSuffix(evType, sui.EventNewUser):
            p.store.InsertNewUser(ev.ParsedJson)
        case strings.HasSuffix(evType, sui.EventDeposit):
            p.store.InsertDeposit(ev.ParsedJson, timeStamp, ev.ID.TxDigest)
        case strings.HasSuffix(evType, sui.EventManagedBlobs):
            p.store.InsertManagedBlob(ev.ParsedJson)
        case strings.HasSuffix(evType, sui.EventWarlotFileStore):
            p.store.InsertPublisherBlob(ev.ParsedJson)
        case strings.HasSuffix(evType, sui.EventRenewDigest):
            p.store.InsertRenewDigest(ev.ParsedJson, timeStamp, ev.ID.TxDigest)
        case strings.HasSuffix(evType, sui.EventBlobUpdate):
            p.store.InsertBlobUpdate(ev.ParsedJson)
        case strings.HasSuffix(evType, sui.EventWithdrawBlob):
            p.store.InsertWithdrawBlob(ev.ParsedJson, timeStamp, ev.ID.TxDigest)
            
        default:
            fallbackJSON, _ := json.MarshalIndent(ev.ParsedJson, "", "  ")
            fmt.Printf("Unhandled %s:\n%s\n", ev.Type, fallbackJSON)
        }
    }
}



func parseTimestampMs(tsMsStr string) (time.Time, error) {
    ms, err := strconv.ParseInt(tsMsStr, 10, 64)
    if err != nil {
        return time.Time{}, err
    }
    // timestampMs is milliseconds since Unix epoch
    sec := ms / 1000
    nsec := (ms % 1000) * int64(time.Millisecond)
    return time.Unix(sec, nsec).UTC(), nil
}
