import re
import sys
import json

ignore_keys = {'type', 'len'}
mapping_keys = {
}

def compare(jm_file_path, json_file_path):
    # jmResult = read_jm_result(jm_file_path)
    # with open('.\\jm.json', 'r') as file:
    #     json.dump(jmResult, file)
    jm_result = read_json_result('.\\jm.json')
    json_result = read_json_result(json_file_path)
    nals = json_result['nals']
    compare_json(jm_result, nals)

def compare_json(jm_json, my_json):
    print(f'nalu length {len(jm_json)}:{len(my_json)}')
    for i in range(len(jm_json)):
        jm_nal = jm_json[i]
        if i >= len(my_json):
            print(f'WRONG: my json has less nalu')
            break
        my_nal = my_json[i]
        for key in jm_nal.keys():
            if key not in my_nal:
                print(f'cannot find key {key}')
            else:
                match key:
                    case 'nalu' | 'sps' | 'pps' | 'sh':
                        compare_obj(jm_nal[key], my_nal[key], i, key)
                    case _:
                        print(f'ignore key {key} in index {i}')

def compare_obj(jm_obj, my_obj, index, parent_key):
    for key in jm_obj.keys():
        if key in ignore_keys:
            continue
        my_key = key
        if key in mapping_keys:
            my_key = mapping_keys[key]
        if my_key not in my_obj:
            print(f'WARN: in {index}th nal\'s object({parent_key}), cannot find key {my_key}({key})')
            continue
        jm_value = jm_obj[key]
        my_value = my_obj[my_key]
        if type(jm_value) is list:
            if type(my_value[0]) is list:
                my_value = [y for mi in my_value for y in mi]
            if len(jm_value) != len(my_value):
                print(f'WARN: in {index}th nal\'s object({parent_key}), list length are not equal {my_key}({key})')
                continue

            wrong_cnt = 0
            for i in range(0, len(jm_value)):
                if jm_value[i] != str(my_value[i]):
                    wrong_cnt += 1
            if wrong_cnt > 0:
                print(f'WRONG: in {index}th nal\'s object({parent_key}), list values({key}) are not equal:({jm_value}), ({my_value})')
        else:
            if jm_value != str(my_value):
                print(f'WRONG: in {index}th nal\'s object({parent_key}), values({key}) are not equal:({jm_value}), ({my_value})')

def read_json_result(file_path):
    """
        used to parse Elixir generated json result
    """
    with open(file_path) as file:
        return json.load(file, strict=False)

nalLineRe = re.compile(r'\s*Annex B NALU .*, len (\d+), forbidden_bit (\d+), nal_reference_idc (\d+), nal_unit_type (\d+)')
lineRe = re.compile(r'@\d+\s+(?P<name>\w+):\s+(?P<field_name>[\w_]+)\s+(?P<binary_value>\d+)\s+\(\s*(?P<value>-?\d+)\)')
mbStartLineRe = re.compile(r'\*+\s+POC:\s+(?P<poc>\d+)\s+.*\s+MB:\s+(?P<mb_num>\d+)\s+Slice:\s+(?P<slice_num>\d+)\s+Type\s+(?P<mb_type>\d+)\s+\*+')
mbLine = re.compile(r'@\d+\s+(?P<name>[\w_]+)\s+\(\s+(?P<value>\d+)\)')
mbLine2 = re.compile(r'@\d+\s+(?P<name>([\w_]+ )+)\s+(?P<value>.*)')

def read_jm_result(file_path):
    """
        used to parse JM generated result
    """
    with open(file_path, 'r') as file:
        nals = []
        curNal = {}
        curSub = {}
        shouldCreateNewSub = True
        for line in file.readlines():
            line = line.strip()
            if len(line) == 0:
                continue
            result = parse_line(line)
            line_type = result['type']
            if line_type == 'NAL':
                if len(curNal) > 0:
                    nals.append(curNal)
                    curNal = {}
                    shouldCreateNewSub = True
                curNal['nalu'] = result
            elif line_type == 'NAL_VALUE':
                name = result['name'].lower()
                fieldName = result['field_name']
                value = result['value']

                # if name in curNal:
                #     print(f'WARN: duplidate sub field in nal with {name}')
                if shouldCreateNewSub:
                    curSub = {}
                    curNal[name] = curSub
                    shouldCreateNewSub = False

                if fieldName in curSub:
                    oldValue = curSub[fieldName]
                    if type(oldValue) is list:
                        oldValue.append(value)
                    else:
                        del curSub[fieldName]
                        curSub[fieldName] = [oldValue, value]
                    # print(f'WARN: dupliate field in {name} with {fieldName}')
                else:
                    curSub[fieldName] = value
            elif line_type == 'MB_START':
                shouldCreateNewSub = True
                pass
            elif line_type == 'MB_VALUE':
                shouldCreateNewSub = True
                pass
            elif line_type == 'MB_ARRAY_VALUE':
                shouldCreateNewSub = True
                pass
            elif line_type == 'UNKNOWN':
                shouldCreateNewSub = True
                print(f'unknown line {line}')
        if len(curNal) > 0:
            nals.append(curNal)
        return nals


def parse_line(line):
    """
    nal: Annex B NALU w/ long startcode, len 27, forbidden_bit 0, nal_reference_idc 3, nal_unit_type 7
    line: @0     SPS: profile_idc                                       01100100 (100) 
    mb start line: *********** POC: 0 (I/P) MB: 0 Slice: 0 Type 2 **********
    mb line: @0      mb_type                                                         (  3)
    mb line2: @3      DC luma 16x16                                         -717    0
    """
    m = nalLineRe.match(line)
    if m is not None:
        return {
            'type': 'NAL',
            'len': m.group(1),
            'forbidden_zero_bit': m.group(2),
            'nal_ref_idc': m.group(3),
            'nal_unit_type': m.group(4),
        }
    m = lineRe.match(line)
    if m is not None:
        return {
            'type': 'NAL_VALUE',
            'name': m.group('name'),
            'field_name': m.group('field_name'),
            'binary_value': m.group('binary_value'),
            'value': m.group('value'),
        }
    m = mbStartLineRe.match(line)
    if m is not None:
        return {
            'type': 'MB_START',
            'poc': m.group('poc'),
            'mb_num': m.group('mb_num'),
            'slice_num': m.group('slice_num'),
            'mb_type': m.group('mb_type'),
        }
    m = mbLine.match(line)
    if m is not None:
        return {
            'type': 'MB_VALUE',
            'name': m.group('name'),
            'value': m.group('value'),
        }
    m = mbLine2.match(line)
    if m is not None:
        return {
            'type': 'MB_ARRAY_VALUE',
            'name': m.group('name'),
            'value': m.group('value'),
        }
    return { 'type': 'UNKNOWN' }

if __name__ == '__main__':
    args = sys.argv
    jm_file_path = args[1]
    json_file_path = args[2]
    compare(jm_file_path, json_file_path)