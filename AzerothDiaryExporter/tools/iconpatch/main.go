package main

import (
	"encoding/binary"
	"errors"
	"fmt"
	"os"
)

const (
	peSignature                    = 0x00004550
	pe32PlusMagic                  = 0x20b
	rtIcon                         = 3
	rtGroupIcon                    = 14
	languageEnglishUS              = 1033
	sectionReadableInitializedData = 0x40000040
)

type iconEntry struct {
	Width, Height, ColorCount, Reserved byte
	Planes, BitCount                    uint16
	Size, Offset                        uint32
	Data                                []byte
	ID                                  uint16
}

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: iconpatch <exe> <ico>")
		os.Exit(2)
	}
	if err := patchIcon(os.Args[1], os.Args[2]); err != nil {
		fmt.Fprintln(os.Stderr, "iconpatch:", err)
		os.Exit(1)
	}
}

func patchIcon(exePath, icoPath string) error {
	exe, err := os.ReadFile(exePath)
	if err != nil {
		return err
	}
	ico, err := os.ReadFile(icoPath)
	if err != nil {
		return err
	}
	entries, err := parseICO(ico)
	if err != nil {
		return err
	}

	if len(exe) < 0x40 {
		return errors.New("invalid PE file")
	}
	peOff := int(binary.LittleEndian.Uint32(exe[0x3c:0x40]))
	if peOff < 0 || peOff+24 > len(exe) || binary.LittleEndian.Uint32(exe[peOff:peOff+4]) != peSignature {
		return errors.New("invalid PE signature")
	}
	coff := peOff + 4
	nsects := int(binary.LittleEndian.Uint16(exe[coff+2 : coff+4]))
	optSize := int(binary.LittleEndian.Uint16(exe[coff+16 : coff+18]))
	opt := coff + 20
	if opt+optSize > len(exe) || binary.LittleEndian.Uint16(exe[opt:opt+2]) != pe32PlusMagic {
		return errors.New("only PE32+ executables are supported")
	}
	sectionAlignment := binary.LittleEndian.Uint32(exe[opt+32 : opt+36])
	fileAlignment := binary.LittleEndian.Uint32(exe[opt+36 : opt+40])
	if sectionAlignment == 0 || fileAlignment == 0 {
		return errors.New("invalid PE alignment")
	}

	numberOfRvaAndSizes := binary.LittleEndian.Uint32(exe[opt+108 : opt+112])
	if numberOfRvaAndSizes < 3 {
		return errors.New("PE has no resource data directory")
	}
	dataDir := opt + 112
	oldResRVA := binary.LittleEndian.Uint32(exe[dataDir+16 : dataDir+20])
	oldResSize := binary.LittleEndian.Uint32(exe[dataDir+20 : dataDir+24])
	if oldResRVA != 0 || oldResSize != 0 {
		return errors.New("executable already contains resources; patch a fresh build")
	}

	sectTable := opt + optSize
	newHeaderOff := sectTable + nsects*40
	firstRaw := uint32(^uint32(0))
	var endVA uint32
	for i := 0; i < nsects; i++ {
		sh := sectTable + i*40
		if sh+40 > len(exe) {
			return errors.New("truncated section table")
		}
		virtualSize := binary.LittleEndian.Uint32(exe[sh+8 : sh+12])
		virtualAddress := binary.LittleEndian.Uint32(exe[sh+12 : sh+16])
		rawSize := binary.LittleEndian.Uint32(exe[sh+16 : sh+20])
		rawPtr := binary.LittleEndian.Uint32(exe[sh+20 : sh+24])
		if rawPtr != 0 && rawPtr < firstRaw {
			firstRaw = rawPtr
		}
		span := virtualSize
		if rawSize > span {
			span = rawSize
		}
		if v := virtualAddress + align(span, sectionAlignment); v > endVA {
			endVA = v
		}
	}
	if uint32(newHeaderOff+40) > firstRaw {
		return errors.New("not enough room in PE headers for resource section")
	}

	newVA := align(endVA, sectionAlignment)
	resource, err := buildResourceSection(entries, newVA)
	if err != nil {
		return err
	}
	virtualSize := uint32(len(resource))
	rawSize := align(virtualSize, fileAlignment)
	newRaw := align(uint32(len(exe)), fileAlignment)

	outLen := int(newRaw + rawSize)
	out := make([]byte, outLen)
	copy(out, exe)
	copy(out[int(newRaw):], resource)

	// New .rsrc section header.
	sh := newHeaderOff
	copy(out[sh:sh+8], []byte{'.', 'r', 's', 'r', 'c', 0, 0, 0})
	binary.LittleEndian.PutUint32(out[sh+8:sh+12], virtualSize)
	binary.LittleEndian.PutUint32(out[sh+12:sh+16], newVA)
	binary.LittleEndian.PutUint32(out[sh+16:sh+20], rawSize)
	binary.LittleEndian.PutUint32(out[sh+20:sh+24], newRaw)
	binary.LittleEndian.PutUint32(out[sh+36:sh+40], sectionReadableInitializedData)

	// COFF section count.
	binary.LittleEndian.PutUint16(out[coff+2:coff+4], uint16(nsects+1))
	// SizeOfInitializedData.
	initData := binary.LittleEndian.Uint32(out[opt+8 : opt+12])
	binary.LittleEndian.PutUint32(out[opt+8:opt+12], initData+rawSize)
	// SizeOfImage.
	binary.LittleEndian.PutUint32(out[opt+56:opt+60], align(newVA+virtualSize, sectionAlignment))
	// Resource data directory (index 2).
	binary.LittleEndian.PutUint32(out[dataDir+16:dataDir+20], newVA)
	binary.LittleEndian.PutUint32(out[dataDir+20:dataDir+24], virtualSize)
	// Checksum is optional for normal user-mode executables. Clear it after modification.
	binary.LittleEndian.PutUint32(out[opt+64:opt+68], 0)

	tmp := exePath + ".iconpatch.tmp"
	if err := os.WriteFile(tmp, out, 0755); err != nil {
		return err
	}
	if err := os.Rename(tmp, exePath); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return nil
}

func parseICO(b []byte) ([]iconEntry, error) {
	if len(b) < 6 {
		return nil, errors.New("ICO file too small")
	}
	if binary.LittleEndian.Uint16(b[0:2]) != 0 || binary.LittleEndian.Uint16(b[2:4]) != 1 {
		return nil, errors.New("invalid ICO header")
	}
	count := int(binary.LittleEndian.Uint16(b[4:6]))
	if count < 1 || count > 255 || 6+count*16 > len(b) {
		return nil, errors.New("invalid ICO entry count")
	}
	entries := make([]iconEntry, 0, count)
	for i := 0; i < count; i++ {
		p := 6 + i*16
		size := binary.LittleEndian.Uint32(b[p+8 : p+12])
		off := binary.LittleEndian.Uint32(b[p+12 : p+16])
		if uint64(off)+uint64(size) > uint64(len(b)) {
			return nil, errors.New("ICO image outside file")
		}
		e := iconEntry{
			Width: b[p], Height: b[p+1], ColorCount: b[p+2], Reserved: b[p+3],
			Planes:   binary.LittleEndian.Uint16(b[p+4 : p+6]),
			BitCount: binary.LittleEndian.Uint16(b[p+6 : p+8]),
			Size:     size, Offset: off, ID: uint16(i + 1),
			Data: append([]byte(nil), b[off:off+size]...),
		}
		entries = append(entries, e)
	}
	return entries, nil
}

func buildResourceSection(icons []iconEntry, baseRVA uint32) ([]byte, error) {
	n := len(icons)
	if n == 0 {
		return nil, errors.New("no icons")
	}
	rootOff := uint32(0)
	iconTypeOff := align(rootOff+16+2*8, 4)
	groupTypeOff := align(iconTypeOff+uint32(16+n*8), 4)

	iconIDOffs := make([]uint32, n)
	cur := align(groupTypeOff+16+8, 4)
	for i := range icons {
		iconIDOffs[i] = cur
		cur = align(cur+16+8, 4)
	}
	groupIDOff := cur
	cur = align(cur+16+8, 4)

	iconDataEntryOffs := make([]uint32, n)
	for i := range icons {
		iconDataEntryOffs[i] = cur
		cur += 16
	}
	groupDataEntryOff := cur
	cur += 16
	cur = align(cur, 4)

	groupData := buildGroupIcon(icons)
	groupDataOff := cur
	cur = align(cur+uint32(len(groupData)), 4)
	iconDataOffs := make([]uint32, n)
	for i, e := range icons {
		iconDataOffs[i] = cur
		cur = align(cur+uint32(len(e.Data)), 4)
	}

	out := make([]byte, cur)
	writeDirHeader(out, rootOff, 0, 2)
	writeDirEntry(out, rootOff+16, rtIcon, iconTypeOff, true)
	writeDirEntry(out, rootOff+24, rtGroupIcon, groupTypeOff, true)

	writeDirHeader(out, iconTypeOff, 0, uint16(n))
	for i, e := range icons {
		writeDirEntry(out, iconTypeOff+16+uint32(i*8), uint32(e.ID), iconIDOffs[i], true)
		writeDirHeader(out, iconIDOffs[i], 0, 1)
		writeDirEntry(out, iconIDOffs[i]+16, languageEnglishUS, iconDataEntryOffs[i], false)
	}

	writeDirHeader(out, groupTypeOff, 0, 1)
	writeDirEntry(out, groupTypeOff+16, 1, groupIDOff, true)
	writeDirHeader(out, groupIDOff, 0, 1)
	writeDirEntry(out, groupIDOff+16, languageEnglishUS, groupDataEntryOff, false)

	for i, e := range icons {
		writeDataEntry(out, iconDataEntryOffs[i], baseRVA+iconDataOffs[i], uint32(len(e.Data)))
		copy(out[iconDataOffs[i]:], e.Data)
	}
	writeDataEntry(out, groupDataEntryOff, baseRVA+groupDataOff, uint32(len(groupData)))
	copy(out[groupDataOff:], groupData)
	return out, nil
}

func buildGroupIcon(icons []iconEntry) []byte {
	b := make([]byte, 6+14*len(icons))
	binary.LittleEndian.PutUint16(b[0:2], 0)
	binary.LittleEndian.PutUint16(b[2:4], 1)
	binary.LittleEndian.PutUint16(b[4:6], uint16(len(icons)))
	for i, e := range icons {
		p := 6 + i*14
		b[p] = e.Width
		b[p+1] = e.Height
		b[p+2] = e.ColorCount
		b[p+3] = e.Reserved
		binary.LittleEndian.PutUint16(b[p+4:p+6], e.Planes)
		binary.LittleEndian.PutUint16(b[p+6:p+8], e.BitCount)
		binary.LittleEndian.PutUint32(b[p+8:p+12], uint32(len(e.Data)))
		binary.LittleEndian.PutUint16(b[p+12:p+14], e.ID)
	}
	return b
}

func writeDirHeader(b []byte, off uint32, named, ids uint16) {
	binary.LittleEndian.PutUint16(b[off+12:off+14], named)
	binary.LittleEndian.PutUint16(b[off+14:off+16], ids)
}

func writeDirEntry(b []byte, off uint32, id, target uint32, directory bool) {
	binary.LittleEndian.PutUint32(b[off:off+4], id)
	if directory {
		target |= 0x80000000
	}
	binary.LittleEndian.PutUint32(b[off+4:off+8], target)
}

func writeDataEntry(b []byte, off, rva, size uint32) {
	binary.LittleEndian.PutUint32(b[off:off+4], rva)
	binary.LittleEndian.PutUint32(b[off+4:off+8], size)
}

func align(v, a uint32) uint32 {
	if a == 0 {
		return v
	}
	return (v + a - 1) &^ (a - 1)
}
