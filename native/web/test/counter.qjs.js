let count = 0;

function buildView() {
  askHost('render', JSON.stringify({
    type: 'Column',
    props: {
      style: {
        padding: '20',
        backgroundColor: '#f5f7ff'
      }
    },
    children: [
      {
        type: 'Container',
        props: {
          style: {
            padding: '16',
            backgroundColor: '#ffffff',
            borderRadius: '12'
          }
        },
        events: {
          tap: 'increment'
        },
        children: [
          {
            type: 'Text',
            props: {
              text: 'QuickJS Counter',
              style: { fontSize: '22', fontWeight: 'bold' }
            }
          },
          {
            type: 'Text',
            props: {
              text: `Current value: ${count}`,
              style: { fontSize: '18', color: '#3247D6' }
            }
          },
          {
            type: 'Text',
            props: {
              text: 'Tap this card or the button below to increment and trigger callbacks',
              style: { fontSize: '14', color: '#666666' }
            }
          },
          {
            type: 'Button',
            props: {
              text: 'Increment in-card'
            },
            events: {
              tap: 'increment'
            }
          }
        ]
      }
    ]
  }));
}

function increment() {
  count += 1;
  askHost('println', `Count changed to ${count}`);
  askHost('updateApp', JSON.stringify({
    source: 'quickjs',
    action: 'counterIncremented',
    value: count
  }));
  buildView();
}

buildView();
