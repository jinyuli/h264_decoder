import re
import sys
import json

def compare(jm_file_path, json_file_path):
    jmResult = read_jm_result(jm_file_path)
    jsonResult = read_json_result(json_file_path)
    print(jsonResult)

def read_json_result(file_path):
    """
        used to parse Elixir generated json result
    """
    with open(file_path) as file:
        return json.load(file)

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
        for line in file.readlines():
            line = line.strip()
            if len(line) == 0:
                continue
            result = parse_line(line)
            line_type = result['type']
            if line_type == 'NAL':
                pass
            elif line_type == 'NAL_VALUE':
                pass
            elif line_type == 'MB_START':
                pass
            elif line_type == 'MB_VALUE':
                pass
            elif line_type == 'MB_ARRAY_VALUE':
                pass
            elif line_type == 'UNKNOWN':
                print(f'unknown line {line}')


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
            'forbidden_bit': m.group(2),
            'nal_reference_idc': m.group(3),
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
    json_file_path = args[1]
    compare(jm_file_path, json_file_path)