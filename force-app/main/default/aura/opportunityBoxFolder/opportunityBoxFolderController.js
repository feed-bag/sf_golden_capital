({
    doInit: function(component, event, helper) {
        var action = component.get('c.getBoxFolderId');
        action.setParams({ recordId: component.get('v.recordId') });
        action.setCallback(this, function(response) {
            if (response.getState() === 'SUCCESS') {
                var folderId = response.getReturnValue();
                if (folderId) {
                    component.set('v.folderId', folderId);
                }
            }
        });
        $A.enqueueAction(action);
    }
})