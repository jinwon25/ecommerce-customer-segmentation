import json, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

path = sys.argv[1] if len(sys.argv) > 1 else 'notebooks/phase1_validation.ipynb'
nb = json.load(open(path, 'r', encoding='utf-8'))
for i, c in enumerate(nb['cells']):
    if c['cell_type'] != 'code':
        continue
    outs = c.get('outputs', [])
    src_head = ''.join(c['source'])[:90].replace('\n', ' / ')
    print(f'--- Cell {i} ---')
    print(f'  source: {src_head}...')
    if not outs:
        print('  (outputs: 비어있음 — 미실행 또는 출력 없음)')
        continue
    for o in outs:
        t = o.get('output_type', '?')
        if t == 'stream':
            txt = ''.join(o.get('text', []))
            print(f'  [stream:{o.get("name", "stdout")}]')
            for line in txt.splitlines():
                print('    ' + line)
        elif t == 'error':
            print(f'  [ERROR] {o.get("ename")}: {o.get("evalue")}')
            for line in o.get('traceback', [])[-8:]:
                print('    ' + line)
        elif t == 'execute_result':
            data = o.get('data', {})
            if 'text/plain' in data:
                txt = ''.join(data['text/plain'])
                print(f'  [result]')
                for line in txt.splitlines()[:25]:
                    print('    ' + line)
        elif t == 'display_data':
            keys = list(o.get('data', {}).keys())
            print(f'  [display_data: {keys}]')
